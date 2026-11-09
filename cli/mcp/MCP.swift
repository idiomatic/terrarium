import Foundation
import TerrariumCore

/// `terrarium mcp`: the verbs as an MCP server on stdio, protocol revision 2026-07-28 (docs/specifications/mcp-2026-07-28).
/// Messages are one JSON-RPC object per line. Every request carries its own `_meta` (protocol version and client
/// capabilities); there is no handshake. A legacy `initialize` is also accepted, and then serves that process the older way.
final class MCPServer {
    static let version = "2026-07-28"
    static let legacyVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    static let serverInfo: [String: Any] = ["name": "terrarium", "version": "0.1.0"]
    static let maxOutput = 1 << 20

    private let writer = NSLock()
    private let state = NSLock()
    private var legacy = false
    private var inflight: [String: Inflight] = [:]

    /// A running `tools/call`: what to do if the client cancels it, and whether it was.
    /// A call in progress. The reader thread cancels it while the call's own thread sets how; a lock keeps them apart, and a
    /// cancellation that comes before there is a way to cancel takes effect as soon as there is one.
    private final class Inflight {
        let cancellable: Bool
        private let lock = NSLock()
        private var cancelled = false
        private var action: (() -> Void)?

        init(cancellable: Bool) { self.cancellable = cancellable }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        func cancel() {
            guard cancellable else { return }
            lock.lock()
            cancelled = true
            let run = action
            lock.unlock()
            run?()
        }

        /// How to cancel the call from now on; run at once if it was cancelled already.
        func onCancel(_ run: @escaping () -> Void) {
            lock.lock()
            action = run
            let now = cancelled
            lock.unlock()
            if now { run() }
        }
    }

    /// Reads requests until the client closes stdin, then exits.
    func run() -> Never {
        signal(SIGPIPE, SIG_IGN)
        while let line = readLine(strippingNewline: true) {
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { handle(line) }
        }
        exit(0)
    }

    // MARK: wire

    private func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        writer.lock()
        defer { writer.unlock() }
        writeAll(STDOUT_FILENO, data + Data([0x0A]))
    }

    private func respond(_ id: Any, _ result: [String: Any]) {
        var result = result
        if !isLegacy {
            result["resultType"] = "complete"
            var meta = result["_meta"] as? [String: Any] ?? [:]
            meta["io.modelcontextprotocol/serverInfo"] = Self.serverInfo
            result["_meta"] = meta
        }
        send(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func fail(_ id: Any?, _ code: Int, _ message: String, data: Any? = nil) {
        var error: [String: Any] = ["code": code, "message": message]
        if let data { error["data"] = data }
        send(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": error])
    }

    private var isLegacy: Bool {
        state.lock()
        defer { state.unlock() }
        return legacy
    }

    // MARK: requests

    private func handle(_ line: String) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) else {
            return fail(nil, -32700, "Parse error")
        }
        guard let message = object as? [String: Any], let method = message["method"] as? String else {
            return fail(nil, -32600, "Invalid Request")
        }
        let params = message["params"] as? [String: Any] ?? [:]
        guard let id = message["id"] else { return notification(method, params) }
        guard id is String || id is NSNumber else { return fail(nil, -32600, "Invalid Request: the id must be a string or a number") }

        switch method {
        case "initialize":
            initialize(id, params)
        case "ping":
            respond(id, [:])
        case "server/discover", "tools/list", "tools/call":
            guard checkMeta(id, params) else { return }
            switch method {
            case "server/discover": discover(id)
            case "tools/list": listTools(id)
            default: call(id, params)
            }
        default:
            fail(id, -32601, "Method not found: \(method)")
        }
    }

    private func notification(_ method: String, _ params: [String: Any]) {
        guard method == "notifications/cancelled", let requestId = params["requestId"] else { return }
        state.lock()
        let running = inflight[Self.key(requestId)]
        state.unlock()
        running?.cancel()
    }

    private static func key(_ id: Any) -> String { id is String ? "s:\(id)" : "n:\(id)" }

    /// Every modern request must name a supported protocol version and carry client capabilities.
    private func checkMeta(_ id: Any, _ params: [String: Any]) -> Bool {
        if isLegacy { return true }
        let meta = params["_meta"] as? [String: Any]
        guard let requested = meta?["io.modelcontextprotocol/protocolVersion"] as? String,
              meta?["io.modelcontextprotocol/clientCapabilities"] is [String: Any] else {
            fail(id, -32602, "Invalid params: _meta needs io.modelcontextprotocol/protocolVersion and io.modelcontextprotocol/clientCapabilities")
            return false
        }
        guard requested == Self.version else {
            fail(id, -32022, "Unsupported protocol version", data: ["supported": [Self.version], "requested": requested])
            return false
        }
        return true
    }

    private func initialize(_ id: Any, _ params: [String: Any]) {
        let requested = params["protocolVersion"] as? String ?? ""
        state.lock()
        legacy = true
        state.unlock()
        respond(id, [
            "protocolVersion": Self.legacyVersions.contains(requested) ? requested : Self.legacyVersions[0],
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": Self.serverInfo,
            "instructions": Self.instructions,
        ])
    }

    private static let instructions = """
        terrarium boots virtual machines on a Mac and drives them. Pull an image, start a VM (the call returns its ID), \
        then look at it with shot and act with click, type, key, and exec. Pass vm to name a VM; with one running it is optional. \
        Use wait after start to know the guest can be driven, and put and get to move files. A VM keeps running until stop. Save its disk changes with commit.
        """

    private func discover(_ id: Any) {
        respond(id, [
            "supportedVersions": [Self.version],
            "capabilities": ["tools": [String: Any]()],
            "instructions": Self.instructions,
            "ttlMs": 3_600_000,
            "cacheScope": "public",
        ])
    }

    // MARK: tools

    private static var tools: [Verb] { allVerbs.filter { !$0.cliOnly } }

    private func listTools(_ id: Any) {
        respond(id, ["tools": Self.tools.map(Self.describe), "ttlMs": 3_600_000, "cacheScope": "public"])
    }

    /// What a client needs beyond the table's summary.
    private static let notes: [String: String] = [
        "start": "The VM keeps running after this returns; use its ID with the other tools and end it with stop. An install (install=windows, macos, or alpine) ends by shutting the guest down and is discarded unless it is saved: pass commit-on-stop PATH here, or call commit with on-stop before it finishes. A Windows install takes several minutes, and its account password is in the result's notes. Without accept-license, Windows setup waits at Microsoft's license page for someone to press Accept (shot, then click). Returning from start does not mean the guest is ready: call wait.",
        "shot": "Returns the screen as a PNG, a second after the last click, move, type, or key. Coordinates for click are pixels of this image. The pointer is in the image where it is: park it out of the way with move.",
        "move": "Moves the pointer without a click, for keeping it out of a shot or for hover.",
        "ps": "With deceased, lists instead the last 20 VMs that ended, with exit status and reason, which tells a VM that powered itself off or failed from one that was stopped.",
        "exec": "Runs the command without a shell, with empty stdin; for shell syntax, make the command a shell (`/bin/sh` with args `-c`, `cmd` with `/c`). Needs the guest helper, which --provision or --install puts in. A non-zero exit status marks the result as an error.",
        "commit": "Saves the VM's disk changes now or when the VM stops: as the file PATH-<imagehash>.overlay (PATH-<guestid>.overlay over an installed guest), or, for an install or a guest booted without an overlay, as the directory PATH.guest. The parent directory must exist and the target must not.",
        "wait": "Blocks until ps would show running (tweaks done) and the helper answers exec; fails at the timeout or if the VM stops. Call it after start, before exec, put, or get. With down it waits for the guest to go down instead (the VM stopped, any on-stop commit saved, or the helper stopped answering), for an install that ends by shutting the guest down or after a shutdown. With reboot it waits for the helper to restart (a new instance ID), so call wait first, then restart the guest, then wait with reboot. Not both.",
        "put": "Reads HOST_PATH on the machine running terrarium. A directory's regular files go under GUEST_PATH, with the same relative paths (empty directories and symlinks are not copied); a file's mode is kept on Linux and macOS. Each file is written whole or not at all, over an existing one. Needs the guest helper.",
        "get": "Writes a file the guest has to a path on the machine running terrarium, whole or not at all. Needs the guest helper; one file per call.",
        "type": "US keyboard ASCII only; a newline presses Return.",
        "clipboard": "Text only, UTF-8 with LF line ends, up to 1 MiB. Needs the guest helper in a graphical session. If the guest has no clipboard, set types the text instead (US keyboard ASCII, up to 4 KiB) and says so; get has no fallback.",
        "tweak": "Runs an embedded script for the guest's OS through the helper, with a timeout (10 seconds by default; the script's header may set it); a non-zero exit status, 124 for a timeout, marks the result as an error. Changes persist only if the VM's overlay is committed.",
    ]

    private static let readOnly: Set<String> = ["images", "ps", "logs", "shot"]

    private static func describe(_ verb: Verb) -> [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []
        func property(_ kind: Kind, _ help: String) -> [String: Any] {
            switch kind {
            case .text: return ["type": "string", "description": help]
            case .integer: return ["type": "integer", "minimum": 1, "description": help]
            case .point: return ["type": "string", "pattern": #"^-?\d+,-?\d+$"#, "description": help + " as two whole numbers, like 10,20"]
            case .choice(let allowed): return ["type": "string", "enum": allowed, "description": help]
            }
        }
        for p in verb.positionals {
            properties[p.name] = property(p.kind, "\(p.metavar): \(p.help)")
            if !p.optional { required.append(p.name) }
        }
        for o in verb.options {
            if o.repeatable {
                properties[o.name] = ["type": "array", "items": property(o.kind, o.help), "description": o.help]
            } else {
                properties[o.name] = o.metavar == nil ? ["type": "boolean", "description": o.help] : property(o.kind, o.help)
            }
        }
        if verb.name == "start" || verb.name == "run", var disk = properties["disk"] as? [String: Any] {
            disk["minimum"] = 4
            disk["maximum"] = 1000
            properties["disk"] = disk
        }
        if verb.targetsVM { properties["vm"] = ["type": "string", "description": "ID of the VM (default: the only running VM)"] }
        if verb.passthrough != nil {
            properties["args"] = ["type": "array", "items": ["type": "string"], "description": "arguments passed to the command unchanged"]
        }
        var schema: [String: Any] = ["type": "object", "properties": properties, "additionalProperties": false]
        if !required.isEmpty { schema["required"] = required }
        let description = verb.summary.prefix(1).uppercased() + verb.summary.dropFirst() + "." + (notes[verb.name].map { " " + $0 } ?? "")
        var tool: [String: Any] = ["name": verb.name, "description": description, "inputSchema": schema]
        if readOnly.contains(verb.name) { tool["annotations"] = ["readOnlyHint": true] }
        else if ["rmi", "stop"].contains(verb.name) { tool["annotations"] = ["destructiveHint": true] }
        return tool
    }

    private func call(_ id: Any, _ params: [String: Any]) {
        guard let name = params["name"] as? String, let verb = Self.tools.first(where: { $0.name == name }) else {
            return fail(id, -32602, "Unknown tool: \(params["name"] as? String ?? "")")
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        let progressToken = (params["_meta"] as? [String: Any])?["progressToken"]
        // Only `exec` can be cancelled; other tools run to the end and answer, so `start` still returns its ID and notes.
        let running = Inflight(cancellable: verb.name == "exec")
        state.lock()
        let duplicate = inflight[Self.key(id)] != nil
        if !duplicate { inflight[Self.key(id)] = running }
        state.unlock()
        if duplicate { return fail(id, -32600, "Invalid Request: request id \(id) is already in use") }

        // A thread of its own, not the global queue: `exec` and `start` block for minutes, and many at once would starve
        // the queue that other calls and `runProgram`'s readers need.
        Thread.detachNewThread { [self] in
            var result: [String: Any]
            do {
                result = try execute(try invocation(verb, arguments: arguments), running, progressToken)
            } catch let error as CLIError {
                result = Self.toolError(error.message)
            } catch {
                result = Self.toolError("\(error)")
            }
            state.lock()
            inflight[Self.key(id)] = nil
            state.unlock()
            // A cancelled request gets no response.
            if !running.isCancelled { respond(id, result) }
        }
    }

    private static func toolError(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }

    private static func text(_ string: String, structured: Any? = nil, isError: Bool = false) -> [String: Any] {
        var result: [String: Any] = ["content": [["type": "text", "text": string]], "isError": isError]
        if let structured { result["structuredContent"] = structured }
        return result
    }

    private func execute(_ inv: Invocation, _ running: Inflight, _ progressToken: Any?) throws -> [String: Any] {
        switch inv.verb.name {
        case "exec", "tweak":
            return try runCommand(inv, running)
        case "start":
            var notes = ""
            var step = 0.0
            let id = try Launch.start(inv) { [self] text in
                notes += text
                guard let progressToken else { return }
                step += 1
                send(["jsonrpc": "2.0", "method": "notifications/progress",
                      "params": ["progressToken": progressToken, "progress": step, "message": text.trimmingCharacters(in: .whitespacesAndNewlines)]])
            }
            let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            var content: [[String: Any]] = [["type": "text", "text": id]]
            if !trimmed.isEmpty { content.append(["type": "text", "text": "Notes from starting the VM:\n" + trimmed]) }
            return ["content": content, "structuredContent": ["id": id, "notes": trimmed], "isError": false]
        default:
            switch try Backend.perform(inv) {
            case .none: return Self.text("ok")
            case .text(let string), .raw(let string): return Self.text(string.isEmpty ? "(nothing)" : string)
            case .png(let data):
                return ["content": [["type": "image", "data": data.base64EncodedString(), "mimeType": "image/png"]], "isError": false]
            case .status(let code): return Self.text("exit status \(code)")
            }
        }
    }

    /// Runs a command in the guest and returns its output whole, each stream limited to `maxOutput` bytes.
    private func runCommand(_ inv: Invocation, _ running: Inflight) throws -> [String: Any] {
        var out = Data(), err = Data()
        var truncated = false
        let status = try Remote.stream(inv, onConnect: { fd in
            running.onCancel { shutdown(fd, SHUT_RDWR) }
        }, sink: { stream, data in
            func add(_ buffer: inout Data) {
                let room = Self.maxOutput - buffer.count
                if data.count > room { truncated = true }
                buffer.append(data.prefix(max(room, 0)))
            }
            if stream == .stdout { add(&out) } else { add(&err) }
        })
        let stdout = String(decoding: out, as: UTF8.self), stderr = String(decoding: err, as: UTF8.self)
        var content: [[String: Any]] = []
        if !stdout.isEmpty { content.append(["type": "text", "text": stdout]) }
        if !stderr.isEmpty { content.append(["type": "text", "text": "stderr:\n" + stderr]) }
        if truncated { content.append(["type": "text", "text": "(output was cut at \(Self.maxOutput) bytes per stream)"]) }
        if status != 0 || content.isEmpty { content.append(["type": "text", "text": "exit status \(status)"]) }
        return [
            "content": content,
            "structuredContent": ["stdout": stdout, "stderr": stderr, "exitStatus": Int(status), "truncated": truncated],
            "isError": status != 0,
        ]
    }
}
