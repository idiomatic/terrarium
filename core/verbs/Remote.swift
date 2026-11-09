import Foundation

/// The verbs that act on a running VM: `shot`, `logs`, `click`, `type`, `key`, and `clipboard`.
public enum Remote {
    /// The VM named by `--vm`, or the only running one.
    static func target(_ inv: Invocation) throws -> Runtime.Info {
        if let reference = inv.values["vm"] { return try Runtime.resolve(reference) }
        let vms = Runtime.list()
        switch vms.count {
        case 1: return vms[0]
        case 0: throw CLIError.failure("no running VM")
        default: throw CLIError.failure("\(vms.count) VMs are running; name one with --vm (\(vms.map(\.id).joined(separator: ", ")))")
        }
    }

    public enum Stream {
        case stdout
        case stderr
    }

    /// Runs `exec`'s command, or `tweak`'s tweak, in the guest, giving its output to `sink` as it arrives, and returns its exit
    /// status (128 plus the signal if it was killed). `onConnect` receives the control socket, which a caller can shut down
    /// to stop waiting.
    public static func stream(_ inv: Invocation, onConnect: ((Int32) -> Void)? = nil, sink: (Stream, Data) -> Void) throws -> Int32 {
        let request: [String: Any]
        // An unknown name is found before a VM is looked for; an ambiguous one waits for the VM's OS to settle it.
        if inv.verb.name == "tweak", !Tweaks.known(inv.values["name"]!) { _ = try Tweaks.resolve(inv.values["name"]!) }
        let info = try target(inv)
        let tweak = inv.verb.name == "tweak" ? try Tweaks.resolve(inv.values["name"]!, guest: info.guest.flatMap { GuestOS(rawValue: $0) }) : nil
        if let tweak {
            // A name that is unknown, or for another OS, is a usage mistake: found here, before anything runs.
            if let guest = info.guest, tweak.os.rawValue != guest {
                throw CLIError.usage("tweak \(tweak.fullName) is for \(tweak.os.rawValue), but VM \(info.id) is \(guest)")
            }
            request = ["verb": "tweak", "name": tweak.fullName]
        } else {
            request = ["verb": "exec", "argv": [inv.values["command"]!] + inv.rest]
        }
        let line = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
        let fd = try controlConnect(Runtime.socketPath(info.id), line, timeout: 0)
        defer { close(fd) }
        onConnect?(fd)
        try readStatus(fd)
        while let frame = HelperProtocol.readFrame(fd) {
            switch frame.kind {
            case HelperProtocol.stdout:
                sink(.stdout, frame.payload)
            case HelperProtocol.stderr:
                sink(.stderr, frame.payload)
            case HelperProtocol.exit:
                guard frame.payload.count == 4 else { throw CLIError.failure("malformed exit status from the guest") }
                let code = Int32(bitPattern: UInt32(frame.payload[0]) << 24 | UInt32(frame.payload[1]) << 16 | UInt32(frame.payload[2]) << 8 | UInt32(frame.payload[3]))
                return HelperProtocol.status(fromExit: code)
            case HelperProtocol.error:
                throw CLIError.failure(String(decoding: frame.payload, as: UTF8.self))
            default:
                break
            }
        }
        throw CLIError.failure("the VM closed the connection before the command finished")
    }

    static func perform(_ inv: Invocation) throws -> Output {
        if inv.verb.name == "exec" || inv.verb.name == "tweak" {
            return .status(try stream(inv) { stream, data in writeAll(stream == .stdout ? STDOUT_FILENO : STDERR_FILENO, data) })
        }
        var request: [String: Any] = ["verb": inv.verb.name]
        switch inv.verb.name {
        case "click":
            let at = inv.point("at")!
            request["at"] = [at.x, at.y]
            request["button"] = inv.values["button"] ?? "left"
            if let to = inv.point("drag-to") { request["dragTo"] = [to.x, to.y] }
            if let scroll = inv.point("scroll") { request["scroll"] = [scroll.x, scroll.y] }
            if request["dragTo"] != nil && request["scroll"] != nil { throw CLIError.usage("--drag-to and --scroll cannot be combined") }
        case "type":
            request["text"] = inv.values["text"]!
        case "key":
            request["chord"] = inv.values["chord"]!
        case "clipboard":
            let action = inv.values["action"]!
            request["action"] = action
            if action == "set" {
                guard let text = inv.values["text"] else { throw CLIError.usage("clipboard set needs the text") }
                request["text"] = text
            } else if inv.values["text"] != nil {
                throw CLIError.usage("clipboard get takes no text")
            }
        default:
            break
        }
        let info = try target(inv)
        let line = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
        let reply = try controlRequest(Runtime.socketPath(info.id), line)
        switch inv.verb.name {
        case "shot": return .png(reply)
        case "logs": return .text(String(decoding: reply, as: UTF8.self).trimmingCharacters(in: .newlines))
        case "clipboard":
            if inv.values["action"] == "get" { return .raw(String(decoding: reply, as: UTF8.self)) }
            return String(decoding: reply, as: UTF8.self) == "typed" ? .text("the guest has no clipboard; typed the text instead") : .none
        default: return .none
        }
    }
}
