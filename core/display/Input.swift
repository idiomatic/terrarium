import Foundation

/// Turns `type` text and `key` chords into X11 keysym events for the VNC keyboard.
enum Input {
    /// `alt` and `win` use the VNC server's Mac-style keysyms: `Meta_L` reaches the guest as Alt, `Alt_L` as the Windows key.
    private static let modifiers: [String: UInt32] = [
        "ctrl": 0xffe3,
        "shift": 0xffe1,
        "alt": 0xffe7,
        "win": 0xffe9,
    ]

    private static let named: [String: UInt32] = [
        "esc": 0xff1b, "escape": 0xff1b,
        "return": 0xff0d, "enter": 0xff0d,
        "tab": 0xff09,
        "space": 0x20,
        "backspace": 0xff08,
        "delete": 0xffff,
        "insert": 0xff63,
        "home": 0xff50, "end": 0xff57,
        "pageup": 0xff55, "pagedown": 0xff56,
        "left": 0xff51, "up": 0xff52, "right": 0xff53, "down": 0xff54,
        "f1": 0xffbe, "f2": 0xffbf, "f3": 0xffc0, "f4": 0xffc1, "f5": 0xffc2, "f6": 0xffc3,
        "f7": 0xffc4, "f8": 0xffc5, "f9": 0xffc6, "f10": 0xffc7, "f11": 0xffc8, "f12": 0xffc9,
    ]

    /// US layout: the unshifted key that produces each shifted character.
    private static let shifted: [Character: Character] = [
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
        "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/", "~": "`",
    ]

    static func chord(_ spec: String) throws -> [(UInt32, Bool)] {
        var parts = spec.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        // A chord ending in "+" names the plus key itself (`ctrl++`, or `+` alone).
        if spec.hasSuffix("+"), parts.count >= 2, parts[parts.count - 1].isEmpty, parts[parts.count - 2].isEmpty {
            parts.removeLast(2)
            parts.append("+")
        }
        guard let last = parts.last, !last.isEmpty else { throw CLIError.failure("missing key in '\(spec)'") }
        var down: [UInt32] = []
        for m in parts.dropLast() {
            guard let sym = modifiers[m.lowercased()] else { throw CLIError.failure("unknown modifier '\(m)'") }
            down.append(sym)
        }
        var key: UInt32
        if let sym = named[last.lowercased()] ?? (parts.count == 1 ? modifiers[last.lowercased()] : nil) {
            key = sym
        } else if last.count == 1, let ch = last.first, ch.isASCII {
            if ch.isUppercase { down.append(modifiers["shift"]!) }
            key = ch.lowercased().unicodeScalars.first!.value
        } else {
            throw CLIError.failure("unknown key '\(last)'")
        }
        return down.map { ($0, true) } + [(key, true), (key, false)] + down.reversed().map { ($0, false) }
    }

    static func text(_ text: String) throws -> [(UInt32, Bool)] {
        var events: [(UInt32, Bool)] = []
        for ch in text {
            // CRLF is one Character in Swift; it and a lone CR are Return too.
            if ch == "\n" || ch == "\r" || ch == "\r\n" { events += try chord("return"); continue }
            if ch == "\t" { events += try chord("tab"); continue }
            guard ch.isASCII, let ascii = ch.asciiValue, ascii >= 0x20, ascii < 0x7f else {
                throw CLIError.failure("cannot type '\(ch)': only US keyboard characters are supported")
            }
            var base = ch
            var needsShift = false
            if let unshifted = shifted[ch] { base = unshifted; needsShift = true }
            else if ch.isUppercase { base = Character(ch.lowercased()); needsShift = true }
            let sym = base.unicodeScalars.first!.value
            if needsShift { events.append((modifiers["shift"]!, true)) }
            events += [(sym, true), (sym, false)]
            if needsShift { events.append((modifiers["shift"]!, false)) }
        }
        return events
    }
}
