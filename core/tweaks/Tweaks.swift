import Foundation

/// OS-specific changes to a guest, each a script that the guest's helper runs: `tweak NAME`, and `--tweak NAME` at start.
/// The scripts are `core/tweaks/<os>/<name>.<ext>`, embedded by `build.zig`; the catalog below names each one's section.
enum Tweaks {
    struct Tweak {
        let os: GuestOS
        let name: String
        /// The `__TERRARIUM` section holding the script (at most 16 characters).
        let section: String

        /// `<os>/<name>`.
        var fullName: String { "\(os.rawValue)/\(name)" }
    }

    static let catalog = [
        Tweak(os: .windows, name: "edge-quiet", section: "tw-edge-quiet"),
        Tweak(os: .windows, name: "no-sleep", section: "tw-win-nosleep"),
        Tweak(os: .windows, name: "no-lock", section: "tw-win-nolock"),
        Tweak(os: .linux, name: "experimental-sleep", section: "tw-exp-sleep"),
        Tweak(os: .linux, name: "alpine-repositories", section: "tw-alpine-repos"),
        Tweak(os: .linux, name: "no-blank", section: "tw-no-blank"),
        Tweak(os: .linux, name: "ubuntu-no-welcome", section: "tw-ubu-welcome"),
        Tweak(os: .macos, name: "no-sleep", section: "tw-mac-nosleep"),
        Tweak(os: .macos, name: "quiet-setup", section: "tw-mac-quiet"),
        Tweak(os: .macos, name: "no-screensaver", section: "tw-mac-nosaver"),
    ]

    /// Seconds a tweak may run when its header gives no `timeout`.
    static let defaultTimeout = 10
    static let maxTimeout = 3600

    /// A tweak with what its header says.
    struct Script {
        let tweak: Tweak
        let text: String
        let description: String
        let timeout: Int

        /// What the helper runs: PowerShell for Windows, `sh -c` for the others.
        var argv: [String] {
            switch tweak.os {
            case .windows:
                // `-EncodedCommand` takes the script as base64 of UTF-16LE, so it can span lines. Progress records are off:
                // with output redirected, PowerShell would write them to standard error as CLIXML.
                let encoded = ("$ProgressPreference = 'SilentlyContinue'\n" + text).data(using: .utf16LittleEndian)?.base64EncodedString() ?? ""
                return ["powershell", "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded]
            case .linux, .macos:
                return ["sh", "-c", text]
            }
        }
    }

    /// The tweak a name stands for: `<os>/<name>`, or a bare `<name>` that only one OS has. A usage error otherwise.
    static func resolve(_ name: String) throws -> Tweak {
        let matches = catalog.filter { name.contains("/") ? $0.fullName == name : $0.name == name }
        switch matches.count {
        case 1: return matches[0]
        case 0: throw CLIError.usage("unknown tweak '\(name)'; known: \(catalog.map(\.fullName).joined(separator: ", "))")
        default: throw CLIError.usage("'\(name)' is ambiguous: \(matches.map(\.fullName).joined(separator: ", "))")
        }
    }

    /// Whether the catalog has a tweak by this name (`<os>/<name>` or a bare `<name>`), however many.
    static func known(_ name: String) -> Bool {
        catalog.contains { name.contains("/") ? $0.fullName == name : $0.name == name }
    }

    /// Like `resolve(_:)`, but a bare name that the guest's OS has resolves to that one, even if another OS has one too.
    static func resolve(_ name: String, guest os: GuestOS?) throws -> Tweak {
        if !name.contains("/"), let os {
            let own = catalog.filter { $0.os == os && $0.name == name }
            if own.count == 1 { return own[0] }
        }
        return try resolve(name)
    }

    /// The tweaks that names stand for, in order, each checked against the guest's OS.
    static func resolve(_ names: [String], for os: GuestOS) throws -> [Tweak] {
        try names.map { name in
            let tweak = try resolve(name, guest: os)
            guard tweak.os == os else { throw CLIError.usage("tweak \(tweak.fullName) is for \(tweak.os.rawValue), but the guest is \(os.rawValue)") }
            return tweak
        }
    }

    static func script(for tweak: Tweak) throws -> Script {
        guard let data = Embedded.section(tweak.section) else { throw CLIError.failure("this terrarium has no \(tweak.fullName) file") }
        let text = String(decoding: data, as: UTF8.self)
        let (description, settings) = header(text)
        let timeout = settings["timeout"].flatMap { Int($0) }.map { min(max($0, 1), maxTimeout) } ?? defaultTimeout
        return Script(tweak: tweak, text: text, description: description, timeout: timeout)
    }

    /// A script's header: its leading `#` comment lines (after a shebang). The first says what the tweak does; later
    /// `key: value` lines are settings, and anything else is ignored.
    static func header(_ text: String) -> (description: String, settings: [String: String]) {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        if lines.first?.hasPrefix("#!") == true { lines.removeFirst() }
        var comments: [String] = []
        for line in lines {
            guard line.hasPrefix("#") else { break }
            comments.append(String(line.dropFirst().drop { $0 == " " }))
        }
        var settings: [String: String] = [:]
        for line in comments.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon]
            guard let first = key.first, first.isLowercase, key.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "-" }) else { continue }
            settings[String(key)] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return (comments.first ?? "", settings)
    }
}
