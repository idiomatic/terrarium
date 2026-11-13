import CommonCrypto
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A minimal RFB (RFC 6143) client: VNC authentication with this process's server's password, raw encoding, one connection
/// per request.
final class RFB {
    private let fd: Int32
    private(set) var width: Int
    private(set) var height: Int
    /// Whether the last screenshot was entirely black (a sleeping display, or a guest not yet drawing).
    private(set) var blank = false
    /// A digest of the last screenshot's pixels, to tell whether the screen has settled.
    private(set) var digest = 0

    init(port: UInt16) throws {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        var timeout = timeval(tv_sec: 15, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        fd = sock
        width = 0
        height = 0
        guard sock >= 0, connected == 0 else {
            Darwin.close(sock)
            throw CLIError.failure("cannot reach the VM's display")
        }
        do {
            _ = try read(12)                                   // server version
            send(Array("RFB 003.008\n".utf8))
            let count = try read(1)[0]
            let types = try read(Int(count))
            guard count > 0, types.contains(2) else { throw CLIError.failure("the display does not ask for its password") }
            send([2])                                          // security: VNC authentication
            send(Self.answer(try read(16), password: PrivateVNC.currentPassword))
            guard try read(4) == [0, 0, 0, 0] else { throw CLIError.failure("the display refused the connection") }
            send([1])                                          // ClientInit: shared
            let init24 = try read(24)
            width = Int(init24[0]) << 8 | Int(init24[1])
            height = Int(init24[2]) << 8 | Int(init24[3])
            _ = try read(Int(init24[20]) << 24 | Int(init24[21]) << 16 | Int(init24[22]) << 8 | Int(init24[23]))
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    deinit { Darwin.close(fd) }

    /// VNC authentication's answer to a 16-byte challenge (RFC 6143, 7.2.2): the challenge encrypted with DES, keyed by the
    /// password's first eight bytes (padded with zeros), each byte's bits reversed, as the original VNC did.
    static func answer(_ challenge: [UInt8], password: String) -> [UInt8] {
        var key = Array(password.utf8.prefix(8)) + [UInt8](repeating: 0, count: max(0, 8 - password.utf8.count))
        key = key.map { byte in (0..<8).reduce(UInt8(0)) { $0 | ((byte >> $1) & 1) << (7 - $1) } }
        var out = [UInt8](repeating: 0, count: 16)
        var moved = 0
        let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmDES), CCOptions(kCCOptionECBMode), key, kCCKeySizeDES,
                             nil, challenge, challenge.count, &out, out.count, &moved)
        return status == kCCSuccess ? out : [UInt8](repeating: 0, count: 16)
    }

    /// Writes a whole message; a write that fails or times out leaves the reads that follow to report it.
    private func send(_ bytes: [UInt8]) {
        writeAll(fd, Data(bytes))
    }

    private func read(_ n: Int) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: n)
        var got = 0
        while got < n {
            let r = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress! + got, n - got) }
            guard r > 0 else { throw CLIError.failure("the display stopped answering") }
            got += r
        }
        return buffer
    }

    private func be16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 255), UInt8(v & 255)] }

    /// Reads server messages until a FramebufferUpdate, whose header (after the type) it returns; the others a server may
    /// send at any time (SetColourMapEntries, Bell, ServerCutText) are read and dropped.
    private func nextUpdate() throws -> [UInt8] {
        while true {
            let type = try read(1)[0]
            if type == 0 { return try read(3) }
            try skip(type)
        }
    }

    /// Reads and drops the rest of a server message other than FramebufferUpdate.
    private func skip(_ type: UInt8) throws {
        switch type {
        case 1:
            let head = try read(5)
            _ = try read((Int(head[3]) << 8 | Int(head[4])) * 6)
        case 2:
            break
        case 3:
            let head = try read(7)
            let length = Int(head[3]) << 24 | Int(head[4]) << 16 | Int(head[5]) << 8 | Int(head[6])
            guard length <= 16 << 20 else { throw CLIError.failure("the display sent an oversized message") }
            _ = try read(length)
        default:
            throw CLIError.failure("unexpected message from the display")
        }
    }

    func key(_ symbol: UInt32, down: Bool) {
        send([4, down ? 1 : 0, 0, 0, UInt8(symbol >> 24 & 255), UInt8(symbol >> 16 & 255), UInt8(symbol >> 8 & 255), UInt8(symbol & 255)])
    }

    func pointer(buttons: Int, x: Int, y: Int) {
        send([5, UInt8(buttons)] + be16(x) + be16(y))
    }

    /// Lets queued input reach the server before the connection closes.
    func flush() { usleep(100_000) }

    /// Keeps the connection open and calls `changed` with the framebuffer's size at once, and again whenever the server announces
    /// a new one (the desktop-size pseudo-encoding), until the connection ends or `keepGoing` (asked every second) says to stop.
    /// Only a 1x1 corner of the screen is requested, so the updates that come with the notices are tiny, and no more than ten
    /// requests are made a second.
    func watchSize(while keepGoing: () -> Bool, _ changed: (CGSize) -> Void) throws {
        send([0, 0, 0, 0, 32, 24, 0, 1, 0, 255, 0, 255, 0, 255, 16, 8, 0, 0, 0, 0])   // 32-bit BGRX
        send([2, 0] + be16(2) + [0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0x21])                 // raw, desktop size
        changed(CGSize(width: width, height: height))
        var requested = false
        while true {
            if !requested {
                send([3, 1] + be16(0) + be16(0) + be16(1) + be16(1))                    // incremental, 1x1 at the corner
                requested = true
            }
            var watch = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            while true {                                                               // the server answers only when something changes
                let ready = poll(&watch, 1, 1_000)
                if ready > 0 { break }
                if ready < 0 && errno != EINTR { throw CLIError.failure("the display connection failed") }
                if !keepGoing() { return }
            }
            guard watch.revents & Int16(POLLIN) != 0 else { throw CLIError.failure("the display closed the connection") }
            // A message other than an update leaves the request outstanding: back to waiting.
            let type = try read(1)[0]
            guard type == 0 else {
                try skip(type)
                continue
            }
            requested = false
            let header = try read(3)
            for _ in 0..<(Int(header[1]) << 8 | Int(header[2])) {
                let r = try read(12)
                let rw = Int(r[4]) << 8 | Int(r[5]), rh = Int(r[6]) << 8 | Int(r[7])
                let encoding = Int32(bitPattern: UInt32(r[8]) << 24 | UInt32(r[9]) << 16 | UInt32(r[10]) << 8 | UInt32(r[11]))
                switch encoding {
                case 0:
                    _ = try read(rw * rh * 4)
                case -223:
                    width = rw
                    height = rh
                    changed(CGSize(width: width, height: height))
                default:
                    throw CLIError.failure("the display sent an unsupported encoding (\(encoding))")
                }
            }
            usleep(100_000)
        }
    }

    /// The whole screen as PNG data.
    func screenshot() throws -> Data {
        guard width > 0, height > 0 else { throw CLIError.failure("the VM's display is not ready") }
        send([0, 0, 0, 0, 32, 24, 0, 1, 0, 255, 0, 255, 0, 255, 16, 8, 0, 0, 0, 0])           // 32-bit BGRX
        send([2, 0] + be16(3) + [0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0x11, 0xFF, 0xFF, 0xFF, 0x21])  // raw, cursor, desktop size
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var complete = false
        // A full update can come as several rectangles; it is complete once they cover the screen.
        var covered = 0
        for _ in 0..<6 where !complete {
            covered = 0
            send([3, 0, 0, 0, 0, 0] + be16(width) + be16(height))
            let header = try nextUpdate()
            for _ in 0..<(Int(header[1]) << 8 | Int(header[2])) {
                let r = try read(12)
                let rx = Int(r[0]) << 8 | Int(r[1]), ry = Int(r[2]) << 8 | Int(r[3])
                let rw = Int(r[4]) << 8 | Int(r[5]), rh = Int(r[6]) << 8 | Int(r[7])
                let encoding = Int32(bitPattern: UInt32(r[8]) << 24 | UInt32(r[9]) << 16 | UInt32(r[10]) << 8 | UInt32(r[11]))
                switch encoding {
                case 0:
                    let data = try read(rw * rh * 4)
                    for row in 0..<rh where ry + row < height {
                        for col in 0..<rw where rx + col < width {
                            let s = (row * rw + col) * 4, o = ((ry + row) * width + rx + col) * 4
                            pixels[o] = data[s]; pixels[o + 1] = data[s + 1]; pixels[o + 2] = data[s + 2]; pixels[o + 3] = 255
                        }
                    }
                    covered += min(rw, max(width - rx, 0)) * min(rh, max(height - ry, 0))
                    if covered >= width * height { complete = true }
                case -239:
                    _ = try read(rw * rh * 4 + ((rw + 7) / 8) * rh)
                case -223:
                    width = rw
                    height = rh
                    pixels = [UInt8](repeating: 0, count: width * height * 4)
                    covered = 0
                    guard width > 0, height > 0 else { throw CLIError.failure("the VM's display is not ready") }
                default:
                    throw CLIError.failure("the display sent an unsupported encoding (\(encoding))")
                }
            }
        }
        digest = pixels.hashValue
        blank = stride(from: 0, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 0 && pixels[$0 + 1] == 0 && pixels[$0 + 2] == 0 }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let png = Optional(NSMutableData()),
              let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else {
            throw CLIError.failure("cannot encode the screenshot")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CLIError.failure("cannot encode the screenshot") }
        return png as Data
    }

    /// Keeps the connection open and follows the whole screen: one incremental update request outstanding at a time, each
    /// update copied into a framebuffer of 32-bit BGRX pixels. `frame` is called with the framebuffer and whether it changed
    /// after each update, and at least every `interval` seconds without one (so overlays can move on a still screen), until
    /// it returns false or the connection ends. A new display size starts a new framebuffer.
    func follow(interval: TimeInterval, _ frame: (_ pixels: UnsafeRawBufferPointer, _ width: Int, _ height: Int, _ changed: Bool) -> Bool) throws {
        guard width > 0, height > 0 else { throw CLIError.failure("the VM's display is not ready") }
        send([0, 0, 0, 0, 32, 24, 0, 1, 0, 255, 0, 255, 0, 255, 16, 8, 0, 0, 0, 0])   // 32-bit BGRX
        send([2, 0] + be16(2) + [0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0x21])                 // raw, desktop size
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        send([3, 0, 0, 0, 0, 0] + be16(width) + be16(height))                          // the whole screen, once
        let timeout = Int32(max(1, interval * 1000))
        while true {
            var watch = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&watch, 1, timeout)
            if ready < 0 && errno != EINTR { throw CLIError.failure("the display connection failed") }
            guard ready > 0 else {
                if !pixels.withUnsafeBytes({ frame($0, width, height, false) }) { return }
                continue
            }
            guard watch.revents & Int16(POLLIN) != 0 else { throw CLIError.failure("the display closed the connection") }
            let type = try read(1)[0]
            guard type == 0 else {
                try skip(type)
                continue
            }
            let header = try read(3)
            for _ in 0..<(Int(header[1]) << 8 | Int(header[2])) {
                let r = try read(12)
                let rx = Int(r[0]) << 8 | Int(r[1]), ry = Int(r[2]) << 8 | Int(r[3])
                let rw = Int(r[4]) << 8 | Int(r[5]), rh = Int(r[6]) << 8 | Int(r[7])
                let encoding = Int32(bitPattern: UInt32(r[8]) << 24 | UInt32(r[9]) << 16 | UInt32(r[10]) << 8 | UInt32(r[11]))
                switch encoding {
                case 0:
                    let data = try read(rw * rh * 4)
                    // Row by row, clipped to the framebuffer.
                    let columns = min(rw, max(width - rx, 0))
                    guard columns > 0 else { continue }
                    data.withUnsafeBytes { source in
                        pixels.withUnsafeMutableBytes { target in
                            for row in 0..<rh where ry + row < height {
                                memcpy(target.baseAddress! + ((ry + row) * width + rx) * 4, source.baseAddress! + row * rw * 4, columns * 4)
                            }
                        }
                    }
                case -223:
                    width = rw
                    height = rh
                    guard width > 0, height > 0 else { throw CLIError.failure("the VM's display went away") }
                    pixels = [UInt8](repeating: 0, count: width * height * 4)
                    send([3, 0, 0, 0, 0, 0] + be16(width) + be16(height))
                default:
                    throw CLIError.failure("the display sent an unsupported encoding (\(encoding))")
                }
            }
            send([3, 1, 0, 0, 0, 0] + be16(width) + be16(height))                    // the next change, incremental
            if !pixels.withUnsafeBytes({ frame($0, width, height, true) }) { return }
        }
    }
}
