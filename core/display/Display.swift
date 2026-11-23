import Foundation

/// Carries out `shot`, `click`, `move`, `type`, and `key` on a VM's display, over its private VNC server.
enum Display {
    /// Where the pointer last was (nil until a `click`), so a wake-up nudge leaves any hover state alone.
    private static let pointerLock = NSLock()
    nonisolated(unsafe) private static var lastPointer: (x: Int, y: Int)?

    /// The mouse buttons a `click --down` holds until its `--up`: every pointer event carries the buttons, so a move, a
    /// click of another button, or a shot's nudge keeps them held. A held key needs nothing: the server keeps it down.
    nonisolated(unsafe) private static var heldButtons = 0

    /// Forgets what `--down` held, without sending anything: for a new display, whose guest holds nothing.
    static func releaseAll() {
        pointerLock.withLock { heldButtons = 0 }
    }

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

    /// Runs a request on a background queue (the VNC server shares the VM's queue, so the main queue must stay free): a
    /// shot's PNG, or nothing for input.
    static func perform(_ request: DisplayRequest, port: UInt16) throws -> Data {
        if case .shot = request { return try shot(port: port) }
        let input = try InputSession(port: port)
        defer { input.rfb.flush() }
        switch request {
        case .shot: break
        case .move(let to, let duration):
            remember(to.x, to.y)
            input.glide(0, from: input.start, to: to, ms: duration)
            usleep(60_000)
        case .type(let text, let interval):
            // With an interval, character by character, as a person types; else all at once.
            if let interval {
                for (index, character) in text.enumerated() {
                    input.play(try Input.text(String(character)))
                    if index < text.count - 1 { usleep(useconds_t(interval * 1000)) }
                }
            } else {
                input.play(try Input.text(text))
            }
        case .key(let chord, let press):
            // A chord's events are its presses, then its releases in reverse; a hold waits between them, and `down` and
            // `up` send only one half.
            let events = try Input.chord(chord)
            let presses = Array(events.prefix { $0.1 }), releases = Array(events.drop { $0.1 })
            switch press {
            case .down: input.play(presses)
            case .up: input.play(releases)
            case .tap, .hold:
                input.play(presses)
                if case .hold(let ms) = press { usleep(useconds_t(ms * 1000)) }
                input.play(releases)
            }
        case .click(let at, let button, let duration, let press):
            input.approach(at, duration: duration)
            switch press {
            case .down, .up:
                // The held buttons go with every later pointer event until the `up`.
                let now = pointerLock.withLock {
                    heldButtons = press == .down ? heldButtons | button.mask : heldButtons & ~button.mask
                    return heldButtons
                }
                input.rfb.pointer(buttons: now, x: at.x, y: at.y)
                input.recording?.pointerEvent(x: at.x, y: at.y, buttons: now)
            case .tap, .hold:
                input.point(button.mask, at)
                if case .hold(let ms) = press { usleep(useconds_t(ms * 1000)) } else { usleep(60_000) }
                input.point(0, at)
            }
        case .drag(let from, let to, let button, let duration):
            input.approach(from, duration: 0)
            input.point(button.mask, from)
            usleep(100_000)
            if duration > 0 {
                input.glide(button.mask, from: from, to: to, ms: duration)
            } else {
                for step in 1...20 {
                    input.point(button.mask, (from.x + (to.x - from.x) * step / 20, from.y + (to.y - from.y) * step / 20))
                    usleep(30_000)
                }
            }
            input.point(0, to)
            remember(to.x, to.y)
        case .scroll(let at, let dx, let dy):
            input.approach(at, duration: 0)
            // Wheel buttons: 8 up, 16 down, 32 left, 64 right; positive amounts scroll down and right.
            for (amount, positive, negative) in [(dy, 16, 8), (dx, 64, 32)] {
                for _ in 0..<abs(amount) {
                    input.point(amount > 0 ? positive : negative, at)
                    input.point(0, at)
                    usleep(30_000)
                }
            }
        }
        return Data()
    }

    /// Nudges the pointer (no click) so a sleeping display wakes, then waits for the screen to settle: the same pixels twice
    /// in a row, and not black (a waking display fades in).
    private static func shot(port: UInt16) throws -> Data {
        let input = try InputSession(port: port)
        defer { input.rfb.flush() }
        let (x, y) = input.start
        input.point(0, (x + 1, y))
        usleep(30_000)
        input.point(0, (x, y))
        usleep(150_000)
        try input.rfb.capture()
        var last = input.rfb, previous = input.rfb.digest
        // The VNC server answers a still screen only once per connection, so each sample gets its own.
        for _ in 0..<8 {
            usleep(300_000)
            let next = try RFB(port: port)
            try next.capture()
            last = next
            if next.digest == previous && !next.blank { break }
            previous = next.digest
        }
        return try last.png()
    }

    /// One call's connection, with what every pointer event needs: the recording that hears of it and the held buttons.
    private struct InputSession {
        let rfb: RFB
        let recording: Recorder?
        let holding: Int
        /// Where the pointer last was, or the screen's center before any.
        let start: (x: Int, y: Int)

        init(port: UInt16) throws {
            let rfb = try RFB(port: port)
            self.rfb = rfb
            (recording, holding, start) = pointerLock.withLock { (recorder, heldButtons, lastPointer ?? (rfb.width / 2, rfb.height / 2)) }
        }

        func point(_ buttons: Int, _ at: (x: Int, y: Int)) {
            rfb.pointer(buttons: buttons | holding, x: at.x, y: at.y)
            recording?.pointerEvent(x: at.x, y: at.y, buttons: buttons | holding)
        }

        func play(_ events: [(UInt32, Bool)]) {
            for (symbol, down) in events {
                rfb.key(symbol, down: down)
                usleep(20_000)
            }
        }

        /// Moves the pointer from one point to another over `ms` milliseconds, about 60 steps a second, eased in and out
        /// (smoothstep), with `buttons` held; at once when `ms` is 0. Ends at the destination.
        func glide(_ buttons: Int, from: (x: Int, y: Int), to: (x: Int, y: Int), ms: Int) {
            let steps = max(1, ms * 60 / 1000)
            for step in 1...steps {
                let p = Double(step) / Double(steps), s = p * p * (3 - 2 * p)
                point(buttons, (from.x + Int((Double(to.x - from.x) * s).rounded()), from.y + Int((Double(to.y - from.y) * s).rounded())))
                if step < steps { usleep(useconds_t(ms * 1000 / steps)) }
            }
        }

        /// Brings the pointer to where a click, drag, or scroll begins, gliding over `duration` milliseconds.
        func approach(_ at: (x: Int, y: Int), duration: Int) {
            remember(at.x, at.y)
            glide(0, from: start, to: at, ms: duration)
            usleep(60_000)
        }
    }
}

/// How long a key or mouse button is pressed: a tap, a hold of so many milliseconds, or only its press or its release.
enum Press: Equatable {
    case tap
    case hold(ms: Int)
    case down
    case up
}

enum MouseButton: String {
    case left
    case middle
    case right

    /// The button's bit in an RFB pointer event.
    var mask: Int {
        switch self {
        case .left: 1
        case .middle: 2
        case .right: 4
        }
    }
}

/// What a display request asks for, parsed once from the owner's request, so an unknown value is refused.
enum DisplayRequest {
    case shot
    case move(to: (x: Int, y: Int), duration: Int)
    case type(String, interval: Int?)
    case key(String, Press)
    case click(at: (x: Int, y: Int), MouseButton, duration: Int, Press)
    case drag(from: (x: Int, y: Int), to: (x: Int, y: Int), MouseButton, duration: Int)
    case scroll(at: (x: Int, y: Int), dx: Int, dy: Int)

    init(verb: String, _ body: [String: Any]) throws {
        func point(_ key: String) throws -> (x: Int, y: Int) {
            guard let pair = body[key] as? [Int], pair.count == 2 else { throw CLIError.failure("\(verb) needs a position") }
            return (pair[0], pair[1])
        }
        let press: Press
        switch (body["phase"] as? String, body["hold"] as? Int) {
        case (nil, nil): press = .tap
        case (nil, let ms?): press = .hold(ms: ms)
        case ("down", nil): press = .down
        case ("up", nil): press = .up
        default: throw CLIError.failure("\(verb) takes a hold, or a phase of down or up")
        }
        let duration = body["duration"] as? Int ?? 0
        switch verb {
        case "shot": self = .shot
        case "move": self = .move(to: try point("at"), duration: duration)
        case "type": self = .type(body["text"] as? String ?? "", interval: (body["interval"] as? Int).flatMap { $0 > 0 ? $0 : nil })
        case "key":
            guard let chord = body["chord"] as? String else { throw CLIError.failure("key needs a chord") }
            self = .key(chord, press)
        case "click":
            guard let button = MouseButton(rawValue: body["button"] as? String ?? "left") else { throw CLIError.failure("click takes a button of left, middle, or right") }
            let at = try point("at")
            if body["dragTo"] != nil {
                self = .drag(from: at, to: try point("dragTo"), button, duration: duration)
            } else if let scroll = body["scroll"] as? [Int], scroll.count == 2 {
                self = .scroll(at: at, dx: scroll[0], dy: scroll[1])
            } else {
                self = .click(at: at, button, duration: duration, press)
            }
        default: throw CLIError.failure("unknown display request '\(verb)'")
        }
    }
}
