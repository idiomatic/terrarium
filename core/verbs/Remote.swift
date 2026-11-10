import Foundation

/// The verbs that act on a running VM: `shot`, `logs`, `click`, `type`, `key`, and `clipboard`.
public enum Remote {
    /// The VM the verb's first argument names (an ID, or a unique prefix).
    static func target(_ inv: Invocation) throws -> Runtime.Info {
        try Runtime.resolve(inv.values["vm"]!)
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

    /// A probe of the helper: its instance ID (empty from a helper that sends none), or nil while it does not answer.
    /// `baseline` is `set` to remember the instance, or `get` to also learn the one remembered.
    private static func probe(_ info: Runtime.Info, baseline: String? = nil) -> (instance: String, baseline: String)? {
        var request = #"{"verb":"helper""#
        if let baseline { request += #","baseline":"\#(baseline)""# }
        guard let reply = try? controlRequest(Runtime.socketPath(info.id), request + "}", timeout: 5) else { return nil }
        let lines = String(decoding: reply, as: UTF8.self).components(separatedBy: "\n")
        return (lines[0], lines.count > 1 ? lines[1] : "")
    }

    /// Waits until the VM is running, its tweaks are done (both show as the state `running`), and its helper answers.
    /// With `--down`, until the VM has stopped (its files gone, so any scheduled commit is saved) or its helper, having
    /// answered, does not. With `--reboot`, until the helper answers with an instance other than the one last found by
    /// `wait` (or, with none found yet, the first one this call sees), which a guest that restarted does.
    static func wait(_ inv: Invocation) throws -> String {
        let info = try target(inv)
        let down = inv.flags.contains("down")
        let reboot = inv.flags.contains("reboot")
        guard !(down && reboot) else { throw CLIError.usage("--down and --reboot cannot be combined") }
        let limit = inv.values["timeout"].flatMap { Int($0) } ?? 600
        guard limit > 0 else { throw CLIError.usage("--timeout must be a positive number of seconds") }
        let deadline = Date().addingTimeInterval(TimeInterval(limit))
        var answered = false
        var previous: String?
        while true {
            guard let now = Runtime.read(info.id) else {
                if down { return "down" }
                throw CLIError.failure("VM \(info.id) has stopped")
            }
            if reboot {
                if previous == nil {
                    previous = probe(info, baseline: "get")?.baseline
                }
                if let seen = probe(info), now.state == "running" {
                    guard !seen.instance.isEmpty else { throw CLIError.failure("this guest's helper sends no instance ID (it predates --reboot); use wait --down, then wait") }
                    if previous?.isEmpty ?? true { previous = seen.instance }
                    if seen.instance != previous {
                        _ = probe(info, baseline: "set")
                        return "rebooted"
                    }
                }
            } else {
                let answers = probe(info, baseline: down ? nil : "set") != nil
                if down {
                    if answers { answered = true } else if answered { return "down" }
                } else if now.state == "running", answers {
                    return "ready"
                }
            }
            guard Date() < deadline else {
                if down { throw CLIError.failure("VM \(info.id) was still up after \(limit) s (\(now.state))") }
                if reboot { throw CLIError.failure("VM \(info.id) did not restart within \(limit) s (\(now.state))") }
                throw CLIError.failure("VM \(info.id) was not ready within \(limit) s (\(now.state == "running" || now.state == "booting" ? "its helper does not answer" : now.state))")
            }
            // A guest that restarts is down for seconds: look often.
            usleep(down || reboot ? 500_000 : 2_000_000)
        }
    }

    /// The regular files under `directory` as (host file, path relative to it), and how many other entries were skipped.
    private static func files(under directory: URL) -> (files: [(URL, String)], skipped: Int) {
        var found: [(URL, String)] = []
        var skipped = 0
        guard let walker = FileManager.default.enumerator(atPath: directory.path) else { return ([], 0) }
        for case let relative as String in walker {
            let url = directory.appendingPathComponent(relative)
            let type = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
            if type == .typeDirectory { continue }
            guard type == .typeRegular else {
                skipped += 1
                continue
            }
            found.append((url, relative))
        }
        return (found.sorted { $0.1 < $1.1 }, skipped)
    }

    /// Sends one file to the guest; returns the bytes sent.
    private static func putFile(_ info: Runtime.Info, _ file: URL, to path: String) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let mode = (attributes[.posixPermissions] as? Int ?? 0o644) & 0o777
        let request: [String: Any] = ["verb": "put", "path": path, "mode": mode]
        let line = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
        let fd = try controlConnect(Runtime.socketPath(info.id), line, timeout: 120)
        defer { close(fd) }
        try readStatus(fd)
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        var total = 0
        // A helper that refuses the file stops reading; its error is still there to read.
        while true {
            let chunk = try input.read(upToCount: HelperProtocol.dataLimit) ?? Data()
            if !writeAll(fd, HelperProtocol.frame(HelperProtocol.dataKind, chunk)) || chunk.isEmpty { break }
            total += chunk.count
        }
        guard let answer = HelperProtocol.readFrame(fd) else { throw CLIError.failure("the VM sent no answer for \(path)") }
        switch answer.kind {
        case HelperProtocol.exit: return total
        case HelperProtocol.error: throw CLIError.failure(String(decoding: answer.payload, as: UTF8.self))
        default: throw CLIError.failure("unexpected answer from the guest's helper")
        }
    }

    static func put(_ inv: Invocation) throws -> String {
        signal(SIGPIPE, SIG_IGN)
        let source = URL(fileURLWithPath: (inv.values["from"]! as NSString).expandingTildeInPath).standardizedFileURL
        let destination = inv.values["to"]!
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory) else { throw CLIError.failure("no such file or directory: \(source.path)") }
        let info = try target(inv)
        var sending: [(URL, String)]
        var skipped = 0
        if isDirectory.boolValue {
            let base = destination.hasSuffix("/") || destination.hasSuffix("\\") ? String(destination.dropLast()) : destination
            let found = files(under: source)
            sending = found.files.map { ($0.0, base + "/" + $0.1) }
            skipped = found.skipped
        } else {
            sending = [(source, destination)]
        }
        var bytes = 0
        for (file, path) in sending { bytes += try putFile(info, file, to: path) }
        let note = skipped > 0 ? "; skipped \(skipped) that are not regular files" : ""
        return "\(sending.count) file\(sending.count == 1 ? "" : "s"), \(bytes) bytes\(note)"
    }

    static func get(_ inv: Invocation) throws -> String {
        let path = inv.values["from"]!
        var destination = URL(fileURLWithPath: (inv.values["to"]! as NSString).expandingTildeInPath).standardizedFileURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue {
            let name = path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
            guard !name.isEmpty else { throw CLIError.usage("\(path) names no file") }
            destination.appendPathComponent(name)
        }
        let info = try target(inv)
        let line = String(decoding: try JSONSerialization.data(withJSONObject: ["verb": "get", "path": path]), as: UTF8.self)
        let fd = try controlConnect(Runtime.socketPath(info.id), line, timeout: 120)
        defer { close(fd) }
        try readStatus(fd)
        // The file appears whole or not at all.
        let partial = destination.appendingPathExtension("terrarium-partial")
        guard FileManager.default.createFile(atPath: partial.path, contents: nil) else { throw CLIError.failure("cannot write \(destination.path)") }
        let output = try FileHandle(forWritingTo: partial)
        var total = 0
        var finished = false
        defer {
            try? output.close()
            if !finished { try? FileManager.default.removeItem(at: partial) }
        }
        while let frame = HelperProtocol.readFrame(fd) {
            switch frame.kind {
            case HelperProtocol.dataKind:
                try output.write(contentsOf: frame.payload)
                total += frame.payload.count
            case HelperProtocol.exit:
                try output.close()
                guard rename(partial.path, destination.path) == 0 else {
                    throw CLIError.failure("cannot write \(destination.path): \(String(cString: strerror(errno)))")
                }
                finished = true
                return "\(total) bytes to \(destination.path)"
            case HelperProtocol.error:
                throw CLIError.failure(String(decoding: frame.payload, as: UTF8.self))
            default:
                break
            }
        }
        throw CLIError.failure("the VM closed the connection before the file ended")
    }

    static func perform(_ inv: Invocation) throws -> Output {
        switch inv.verb.name {
        case "wait": return .text(try wait(inv))
        case "put": return .text(try put(inv))
        case "get": return .text(try get(inv))
        default: break
        }
        if inv.verb.name == "exec" || inv.verb.name == "tweak" {
            return .status(try stream(inv) { stream, data in writeAll(stream == .stdout ? STDOUT_FILENO : STDERR_FILENO, data) })
        }
        var request: [String: Any] = ["verb": inv.verb.name]
        switch inv.verb.name {
        case "resize":
            let parts = inv.values["size"]!.split(separator: "x").compactMap { Int($0) }
            guard parts.count == 2, parts.allSatisfy({ $0 >= 64 && $0 <= 16384 }) else {
                throw CLIError.usage("resize takes a size like 1280x800: each side from 64 to 16384 pixels")
            }
            request["size"] = parts
        case "move":
            let at = inv.point("at")!
            request["at"] = [at.x, at.y]
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
