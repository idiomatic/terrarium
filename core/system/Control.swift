import Foundation

private func socketAddress(_ path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
        throw CLIError.failure("socket path is too long: \(path)")
    }
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
    return address
}

private func withAddress<T>(_ address: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
    withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
}

/// One client's reply: any number of `send`s from any thread, then `finish`.
/// A reply is `ok` or `error: MESSAGE`, a newline, then payload bytes (see `ok(_:)` and `failed(_:)`).
/// Calling it with data sends and finishes.
final class Reply {
    /// The client's socket, for watching it hang up while a command runs.
    let fd: Int32
    private let lock = NSLock()
    private var finished = false

    init(_ fd: Int32) { self.fd = fd }

    /// Returns false when the client has gone away.
    @discardableResult
    func send(_ data: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        return data.withUnsafeBytes { raw in
            var done = 0
            while done < raw.count {
                let n = write(fd, raw.baseAddress! + done, raw.count - done)
                if n <= 0 { return false }
                done += n
            }
            return true
        }
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        if !finished {
            finished = true
            Darwin.close(fd)
        }
    }

    func callAsFunction(_ data: Data) {
        send(data)
        finish()
    }
}

/// Serves one-line requests on a Unix socket. Connections are accepted, and their requests read, off the main queue (which
/// the VM and its display share), so a client that sends nothing holds up no one; the handler runs on the main queue and
/// replies possibly later.
final class ControlServer {
    typealias Handler = (_ request: String, _ reply: Reply) -> Void

    private let path: String
    private let source: DispatchSourceRead

    init(path: String, handler: @escaping Handler) throws {
        self.path = path
        unlink(path)
        var address = try socketAddress(path)
        let listening = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listening >= 0,
              withAddress(&address, { bind(listening, $0, $1) }) == 0,
              listen(listening, 8) == 0 else {
            throw CLIError.failure("cannot listen on \(path): \(String(cString: strerror(errno)))")
        }
        chmod(path, 0o600)
        source = DispatchSource.makeReadSource(fileDescriptor: listening, queue: DispatchQueue(label: "terrarium.control"))
        source.setEventHandler {
            let client = accept(listening, nil, nil)
            guard client >= 0 else { return }
            DispatchQueue.global().async {
                let request = ControlServer.readRequest(client)
                DispatchQueue.main.async { handler(request, Reply(client)) }
            }
        }
        // The listening socket is closed once the source no longer watches it.
        source.setCancelHandler { Darwin.close(listening) }
        source.resume()
    }

    /// The most a request line holds: a clipboard of 1 MiB, JSON-escaped, fits.
    private static let maxRequest = 8 << 20

    /// The request line: up to a newline, the end of the stream, or `maxRequest`, waiting at most two seconds for each read.
    private static func readRequest(_ client: Int32) -> String {
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 << 10)
        while data.count < maxRequest {
            let n = read(client, &buffer, buffer.count)
            if n <= 0 { break }
            if let newline = buffer[0..<n].firstIndex(of: 0x0A) {
                data.append(contentsOf: buffer[0..<newline])
                break
            }
            data.append(contentsOf: buffer[0..<n])
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func close() {
        source.cancel()
        unlink(path)
    }
}

func ok(_ payload: Data = Data()) -> Data { Data("ok\n".utf8) + payload }
func failed(_ message: String) -> Data { Data("error: \(message)\n".utf8) }

/// Connects to a VM's control socket and sends one request. `timeout` limits each wait for a reply; 0 waits forever.
func controlConnect(_ path: String, _ request: String, timeout: Int) throws -> Int32 {
    var address = try socketAddress(path)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0, withAddress(&address, { connect(fd, $0, $1) }) == 0 else {
        Darwin.close(fd)
        throw CLIError.failure("cannot reach the VM: \(String(cString: strerror(errno)))")
    }
    if timeout > 0 {
        var limit = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
    }
    writeAll(fd, Data((request + "\n").utf8))
    return fd
}

/// Reads a reply's first line: `ok`, or throws the `error:` message.
func readStatus(_ fd: Int32) throws {
    var line = [UInt8]()
    var byte: UInt8 = 0
    while read(fd, &byte, 1) == 1 {
        if byte == 0x0A { break }
        line.append(byte)
    }
    let status = String(decoding: line, as: UTF8.self)
    guard status == "ok" else {
        throw CLIError.failure(status.hasPrefix("error: ") ? String(status.dropFirst(7)) : (status.isEmpty ? "the VM sent no reply" : status))
    }
}

/// Sends one request to a VM's control socket and returns the reply's payload; an `error:` reply throws.
func controlRequest(_ path: String, _ request: String, timeout: Int = 60) throws -> Data {
    let fd = try controlConnect(path, request, timeout: timeout)
    defer { close(fd) }
    var reply = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    var timedOut = false
    while true {
        let n = read(fd, &buffer, buffer.count)
        if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { timedOut = true }
        if n <= 0 { break }
        reply.append(contentsOf: buffer[0..<n])
    }
    guard let newline = reply.firstIndex(of: 0x0A) else {
        throw CLIError.failure(timedOut ? "the VM did not reply within \(timeout) seconds" : "the VM sent no reply")
    }
    let status = String(decoding: reply[reply.startIndex..<newline], as: UTF8.self)
    guard status == "ok" else {
        throw CLIError.failure(status.hasPrefix("error: ") ? String(status.dropFirst(7)) : status)
    }
    return Data(reply[reply.index(after: newline)...])
}
