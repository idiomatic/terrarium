import Foundation

/// Carries out `shot`, `click`, `type`, and `key` on a VM's display, over its private VNC server.
enum Display {
    /// Where the pointer last was (nil until a `click`), so a wake-up nudge leaves any hover state alone.
    private static let pointerLock = NSLock()
    nonisolated(unsafe) private static var lastPointer: (x: Int, y: Int)?

    private static func remember(_ x: Int, _ y: Int) {
        pointerLock.withLock { lastPointer = (x, y) }
    }

    /// Runs on a background queue: the VNC server shares the VM's queue, so the main queue must stay free.
    static func perform(_ verb: String, _ body: [String: Any], port: UInt16) throws -> Data {
        let rfb = try RFB(port: port)
        defer { rfb.flush() }
        func play(_ events: [(UInt32, Bool)]) {
            for (symbol, down) in events {
                rfb.key(symbol, down: down)
                usleep(20_000)
            }
        }
        switch verb {
        case "shot":
            // Nudge the pointer first (no click) so a sleeping display wakes, then wait for the screen to settle:
            // the same pixels twice in a row, and not black (a waking display fades in).
            let (x, y) = pointerLock.withLock { lastPointer } ?? (rfb.width / 2, rfb.height / 2)
            rfb.pointer(buttons: 0, x: x + 1, y: y)
            usleep(30_000)
            rfb.pointer(buttons: 0, x: x, y: y)
            usleep(150_000)
            var png = try rfb.screenshot()
            var previous = rfb.digest
            // The VNC server answers a still screen only once per connection, so each sample gets its own.
            for _ in 0..<8 {
                usleep(300_000)
                let next = try RFB(port: port)
                png = try next.screenshot()
                if next.digest == previous && !next.blank { break }
                previous = next.digest
            }
            return png
        case "type":
            play(try Input.text(body["text"] as? String ?? ""))
        case "key":
            play(try Input.chord(body["chord"] as? String ?? ""))
        default:
            guard let at = body["at"] as? [Int], at.count == 2 else { throw CLIError.failure("click needs a position") }
            let mask = ["left": 1, "middle": 2, "right": 4][body["button"] as? String ?? "left"] ?? 1
            remember(at[0], at[1])
            rfb.pointer(buttons: 0, x: at[0], y: at[1])
            usleep(60_000)
            if let scroll = body["scroll"] as? [Int], scroll.count == 2 {
                // Wheel buttons: 8 up, 16 down, 32 left, 64 right; positive amounts scroll down and right.
                for (amount, positive, negative) in [(scroll[1], 16, 8), (scroll[0], 64, 32)] {
                    for _ in 0..<abs(amount) {
                        rfb.pointer(buttons: amount > 0 ? positive : negative, x: at[0], y: at[1])
                        rfb.pointer(buttons: 0, x: at[0], y: at[1])
                        usleep(30_000)
                    }
                }
            } else if let to = body["dragTo"] as? [Int], to.count == 2 {
                rfb.pointer(buttons: mask, x: at[0], y: at[1])
                usleep(100_000)
                for step in 1...20 {
                    rfb.pointer(buttons: mask, x: at[0] + (to[0] - at[0]) * step / 20, y: at[1] + (to[1] - at[1]) * step / 20)
                    usleep(30_000)
                }
                rfb.pointer(buttons: 0, x: to[0], y: to[1])
                remember(to[0], to[1])
            } else {
                rfb.pointer(buttons: mask, x: at[0], y: at[1])
                usleep(60_000)
                rfb.pointer(buttons: 0, x: at[0], y: at[1])
            }
        }
        return Data()
    }
}
