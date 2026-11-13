import Foundation

/// Carries out `shot`, `click`, `move`, `type`, and `key` on a VM's display, over its private VNC server.
enum Display {
    /// Where the pointer last was (nil until a `click`), so a wake-up nudge leaves any hover state alone.
    private static let pointerLock = NSLock()
    nonisolated(unsafe) private static var lastPointer: (x: Int, y: Int)?

    private static func remember(_ x: Int, _ y: Int) {
        pointerLock.withLock { lastPointer = (x, y) }
    }

    /// Where the pointer last was, for a recording that draws it.
    static var pointer: (x: Int, y: Int)? { pointerLock.withLock { lastPointer } }

    /// The VM's recording, if any, which hears of every pointer event sent.
    nonisolated(unsafe) private static var recorder: Recorder?

    static func setRecorder(_ recording: Recorder?) {
        pointerLock.withLock { recorder = recording }
    }

    /// Runs on a background queue: the VNC server shares the VM's queue, so the main queue must stay free.
    static func perform(_ verb: String, _ body: [String: Any], port: UInt16) throws -> Data {
        let rfb = try RFB(port: port)
        defer { rfb.flush() }
        let recording = pointerLock.withLock { recorder }
        func point(_ buttons: Int, _ x: Int, _ y: Int) {
            rfb.pointer(buttons: buttons, x: x, y: y)
            recording?.pointerEvent(x: x, y: y, buttons: buttons)
        }
        func play(_ events: [(UInt32, Bool)]) {
            for (symbol, down) in events {
                rfb.key(symbol, down: down)
                usleep(20_000)
            }
        }
        /// Moves the pointer from one point to another over `ms` milliseconds, about 60 steps a second, eased in and out
        /// (smoothstep), with `buttons` held; at once when `ms` is 0. Ends at the destination.
        func glide(_ buttons: Int, from: (Int, Int), to: (Int, Int), ms: Int) {
            let steps = max(1, ms * 60 / 1000)
            for step in 1...steps {
                let p = Double(step) / Double(steps), s = p * p * (3 - 2 * p)
                point(buttons, from.0 + Int((Double(to.0 - from.0) * s).rounded()), from.1 + Int((Double(to.1 - from.1) * s).rounded()))
                if step < steps { usleep(useconds_t(ms * 1000 / steps)) }
            }
        }
        let duration = body["duration"] as? Int ?? 0
        let start = pointerLock.withLock { lastPointer } ?? (rfb.width / 2, rfb.height / 2)
        switch verb {
        case "shot":
            // Nudge the pointer first (no click) so a sleeping display wakes, then wait for the screen to settle:
            // the same pixels twice in a row, and not black (a waking display fades in).
            let (x, y) = pointerLock.withLock { lastPointer } ?? (rfb.width / 2, rfb.height / 2)
            point(0, x + 1, y)
            usleep(30_000)
            point(0, x, y)
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
        case "move":
            guard let at = body["at"] as? [Int], at.count == 2 else { throw CLIError.failure("move needs a position") }
            remember(at[0], at[1])
            glide(0, from: start, to: (at[0], at[1]), ms: duration)
            usleep(60_000)
        case "type":
            // With an interval, character by character, as a person types; else all at once.
            let text = body["text"] as? String ?? ""
            if let interval = body["interval"] as? Int, interval > 0 {
                for (index, character) in text.enumerated() {
                    play(try Input.text(String(character)))
                    if index < text.count - 1 { usleep(useconds_t(interval * 1000)) }
                }
            } else {
                play(try Input.text(text))
            }
        case "key":
            play(try Input.chord(body["chord"] as? String ?? ""))
        default:
            guard let at = body["at"] as? [Int], at.count == 2 else { throw CLIError.failure("click needs a position") }
            let mask = ["left": 1, "middle": 2, "right": 4][body["button"] as? String ?? "left"] ?? 1
            let dragTo = body["dragTo"] as? [Int]
            remember(at[0], at[1])
            // A duration glides to the click, or, for a drag, sets how long the drag takes.
            glide(0, from: start, to: (at[0], at[1]), ms: dragTo == nil ? duration : 0)
            usleep(60_000)
            if let scroll = body["scroll"] as? [Int], scroll.count == 2 {
                // Wheel buttons: 8 up, 16 down, 32 left, 64 right; positive amounts scroll down and right.
                for (amount, positive, negative) in [(scroll[1], 16, 8), (scroll[0], 64, 32)] {
                    for _ in 0..<abs(amount) {
                        point(amount > 0 ? positive : negative, at[0], at[1])
                        point(0, at[0], at[1])
                        usleep(30_000)
                    }
                }
            } else if let to = dragTo, to.count == 2 {
                point(mask, at[0], at[1])
                usleep(100_000)
                if duration > 0 {
                    glide(mask, from: (at[0], at[1]), to: (to[0], to[1]), ms: duration)
                } else {
                    for step in 1...20 {
                        point(mask, at[0] + (to[0] - at[0]) * step / 20, at[1] + (to[1] - at[1]) * step / 20)
                        usleep(30_000)
                    }
                }
                point(0, to[0], to[1])
                remember(to[0], to[1])
            } else {
                point(mask, at[0], at[1])
                usleep(60_000)
                point(0, at[0], at[1])
            }
        }
        return Data()
    }
}
