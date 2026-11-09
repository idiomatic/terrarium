import Foundation
import Virtualization

/// The host side of the guest helper's vsock protocol (see `guest/helper/protocol.zig`).
/// Frames are a kind byte, a big-endian u32 length, and the payload.
public enum HelperProtocol {
    /// The status an exit frame reports: a negated signal number (1 to 64) becomes 128 plus the signal; anything else is the
    /// command's exit code as is, which on Windows can be any 32-bit value.
    static func status(fromExit code: Int32) -> Int32 {
        (-64 ... -1).contains(code) ? 128 - code : code
    }

    /// The CLI's own exit status for a command's: a process can exit only with 0 to 255, so a code outside that is 1.
    public static func processStatus(_ code: Int32) -> Int32 {
        (0...255).contains(code) ? code : 1
    }

    static let port: UInt32 = 4242
    static let maxFrame = 16 << 20

    static let hello: UInt8 = 0x00
    static let exec: UInt8 = 0x01
    static let clipboardGetKind: UInt8 = 0x02
    static let clipboardSetKind: UInt8 = 0x03
    static let stdout: UInt8 = 0x10
    static let stderr: UInt8 = 0x11
    static let exit: UInt8 = 0x12
    static let clipboardKind: UInt8 = 0x13
    static let error: UInt8 = 0x1f

    /// The most clipboard text moved at once.
    public static let clipboardLimit = 1 << 20
    /// The helper's error text for a guest with no clipboard to use (no session, or no tool).
    static let noClipboard = "no clipboard"

    static func frame(_ kind: UInt8, _ payload: Data) -> Data {
        var length = UInt32(payload.count).bigEndian
        return Data([kind]) + Data(bytes: &length, count: 4) + payload
    }

    /// Reads one whole frame, header included, or nil at end of stream; a frame over the limit is an error frame instead.
    static func readFrame(_ fd: Int32) -> (kind: UInt8, payload: Data, raw: Data)? {
        guard let header = readExactly(fd, 5) else { return nil }
        let length = Int(header[1]) << 24 | Int(header[2]) << 16 | Int(header[3]) << 8 | Int(header[4])
        guard length <= maxFrame else {
            let message = Data("the guest's helper sent a frame of \(length) bytes, over the \(maxFrame)-byte limit".utf8)
            return (error, message, frame(error, message))
        }
        guard let payload = length == 0 ? Data() : readExactly(fd, length) else { return nil }
        return (header[0], payload, header + payload)
    }

    /// Why a clipboard exchange failed: the guest has no clipboard to use, or the exchange failed otherwise.
    enum ClipboardFailure: Error {
        case unavailable
        case failed(String)
    }

    /// One request and its single answer over `connection`, which it closes. Blocks; call it off the main queue.
    private static func exchange(_ kind: UInt8, _ payload: Data, over connection: VZVirtioSocketConnection) throws -> (kind: UInt8, payload: Data) {
        defer { connection.close() }
        let fd = connection.fileDescriptor
        var timeout = timeval(tv_sec: 15, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        guard writeAll(fd, frame(kind, payload)) else { throw ClipboardFailure.failed("cannot reach the guest's helper") }
        guard let answer = readFrame(fd) else { throw ClipboardFailure.failed("the guest's helper did not answer") }
        if answer.kind == error {
            let text = String(decoding: answer.payload, as: UTF8.self)
            throw text == noClipboard ? ClipboardFailure.unavailable : ClipboardFailure.failed(text)
        }
        return (answer.kind, answer.payload)
    }

    /// The guest's clipboard text, with LF line ends.
    static func fetchClipboard(over connection: VZVirtioSocketConnection) throws -> String {
        let answer = try exchange(clipboardGetKind, Data(), over: connection)
        guard answer.kind == clipboardKind else { throw ClipboardFailure.failed("unexpected answer from the guest's helper") }
        return String(decoding: answer.payload, as: UTF8.self)
    }

    /// Replaces the guest's clipboard text with `text`, which has LF line ends.
    static func storeClipboard(_ text: String, over connection: VZVirtioSocketConnection) throws {
        let answer = try exchange(clipboardSetKind, Data(text.utf8), over: connection)
        guard answer.kind == exit else { throw ClipboardFailure.failed("unexpected answer from the guest's helper") }
    }

    /// Runs `argv` in the guest and relays the helper's frames to `reply` until the command ends.
    /// If the client goes away the connection closes, and the helper kills the command.
    /// A command still running after `timeout` seconds is killed the same way: `timedOut` is sent as standard error, then
    /// the exit status 124.
    static func relayExec(_ argv: [String], over connection: VZVirtioSocketConnection, to reply: Reply,
                          timeout: TimeInterval? = nil, timedOut: String = "") {
        let limit = timeout.map { Date().addingTimeInterval($0) }
        let fd = connection.fileDescriptor
        defer {
            connection.close()
            reply.finish()
        }
        guard let json = try? JSONSerialization.data(withJSONObject: ["argv": argv]),
              writeAll(fd, frame(exec, json)) else {
            reply.send(failed("cannot send the command to the guest"))
            return
        }
        reply.send(ok())
        while true {
            // The client sends nothing after its request, so its socket turning readable means it hung up.
            var watch = [pollfd(fd: fd, events: Int16(POLLIN), revents: 0), pollfd(fd: reply.fd, events: Int16(POLLIN), revents: 0)]
            let wait = limit.map { Int32(max(0, min($0.timeIntervalSinceNow * 1000, Double(Int32.max)))) } ?? -1
            let ready = poll(&watch, 2, wait)
            if ready == 0 {
                reply.send(frame(stderr, Data(timedOut.utf8)))
                reply.send(frame(exit, Data([0, 0, 0, 124])))
                return
            }
            guard ready > 0 else { return }
            if watch[1].revents != 0 { return }
            guard let (kind, _, raw) = readFrame(fd) else { break }
            guard reply.send(raw) else { return }
            if kind == exit || kind == error { return }
        }
        reply.send(frame(error, Data("the guest's helper closed the connection".utf8)))
    }
}

func readExactly(_ fd: Int32, _ count: Int) -> Data? {
    var buffer = [UInt8](repeating: 0, count: count)
    var got = 0
    while got < count {
        let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress! + got, count - got) }
        if n <= 0 { return nil }
        got += n
    }
    return Data(buffer)
}
