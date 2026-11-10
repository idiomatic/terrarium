import Foundation
import Virtualization

/// Running tweaks (see `core/tweaks/`) in the guest: on request, and as `--tweak` asks at start.
extension Owner {
    /// The guest's OS, from its plan.
    var guestOS: GuestOS { GuestOS(rawValue: LayerManifest.name(of: plan.kind)) ?? .linux }

    /// How long a `tweak` request waits for the helper to answer, and how long `--tweak` does while the guest boots.
    private static let requestWait: TimeInterval = 120
    private static let bootWait: TimeInterval = 600
    /// The most of a failed tweak's output that is shown.
    private static let outputLimit = 16 << 10

    /// Connects to the guest's helper, trying again each second until `deadline` or until the VM stops; nil when it never
    /// answered. A Windows guest that resets while it is tried gets a new VM, which the next try finds.
    func connectHelper(until deadline: Date, _ done: @escaping (VZVirtioSocketConnection?) -> Void) {
        guard !stopping, let device = vm.socketDevices.first as? VZVirtioSocketDevice else { return done(nil) }
        // Main queue only. A connect on a VM that was replaced meanwhile (a Windows guest's reset in its setup phase) can
        // never answer, so each try gives up after ten seconds and the next one is made on the current VM.
        var settled = false
        device.__connect(toPort: HelperProtocol.port) { [self] connection, _ in
            DispatchQueue.main.async {
                if settled {
                    connection?.close()
                    return
                }
                settled = true
                if let connection { return done(connection) }
                guard Date() < deadline else { return done(nil) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.connectHelper(until: deadline, done) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [self] in
            guard !settled else { return }
            settled = true
            guard Date() < deadline else { return done(nil) }
            connectHelper(until: deadline, done)
        }
    }

    /// Moves the state from `booting` to `running` once the helper answers (or after `bootWait`, with a note, so a guest
    /// whose helper never starts does not stay `booting`). Does nothing while another call is waiting.
    func watchHelper() {
        guard !helperWatching else { return }
        helperWatching = true
        connectHelper(until: Date().addingTimeInterval(Owner.bootWait)) { [self] connection in
            connection?.close()
            helperWatching = false
            guard !stopping, info.state == "booting" else { return }
            if connection == nil { note("terrarium: the guest's helper did not answer within \(Int(Owner.bootWait)) s") }
            info.state = "running"
            try? Runtime.write(info)
        }
    }

    /// A `tweak` request: runs the tweak and relays the helper's frames, as `exec` does.
    func runTweak(_ body: [String: Any], _ reply: Reply) {
        guard let name = body["name"] as? String else { return reply(failed("tweak needs a name")) }
        let script: Tweaks.Script
        do {
            let tweak = try Tweaks.resolve([name], for: guestOS)[0]
            script = try Tweaks.script(for: tweak)
        } catch {
            return reply(failed((error as? CLIError)?.message ?? "\(error)"))
        }
        connectHelper(until: Date().addingTimeInterval(Owner.requestWait)) { connection in
            guard let connection else {
                return reply(failed("the guest's helper is not reachable (vsock port \(HelperProtocol.port)); is it running?"))
            }
            DispatchQueue.global().async {
                HelperProtocol.relayExec(script.argv, over: connection, to: reply, timeout: TimeInterval(script.timeout),
                                         timedOut: Owner.timeoutNote(script))
            }
        }
    }

    private static func timeoutNote(_ script: Tweaks.Script) -> String {
        "terrarium: tweak \(script.tweak.fullName) timed out after \(script.timeout) s\n"
    }

    /// Runs `--tweak`'s tweaks one after another, as soon as the helper answers. A tweak that fails stops the VM and ends
    /// the process with an error; a Windows reset that interrupts one runs it again (a tweak is safe to repeat).
    func runPendingTweaks() {
        guard let name = pendingTweaks.first, !stopping else {
            if pendingTweaks.isEmpty, info.state.hasPrefix("tweaking") {
                info.state = "running"
                try? Runtime.write(info)
            }
            return
        }
        let script: Tweaks.Script
        do {
            script = try Tweaks.script(for: try Tweaks.resolve(name))
        } catch {
            return failAndExit(["terrarium: tweak \(name) cannot run: \((error as? CLIError)?.message ?? "\(error)")"])
        }
        info.state = "tweaking \(name)"
        try? Runtime.write(info)
        let resetsBefore = resets
        connectHelper(until: Date().addingTimeInterval(Owner.bootWait)) { [self] connection in
            guard let connection else {
                return failAndExit(["terrarium: tweak \(name) failed (the guest's helper did not answer)"])
            }
            DispatchQueue.global().async { [self] in
                let (status, output) = Owner.collect(script, over: connection)
                DispatchQueue.main.async { [self] in
                    if status == 0 {
                        pendingTweaks.removeFirst()
                        return runPendingTweaks()
                    }
                    if resets != resetsBefore, !stopping { return runPendingTweaks() }
                    let why = status == 124 && output.hasSuffix(Owner.timeoutNote(script)) ? "timed out after \(script.timeout) s" : "exit \(status)"
                    let note = Owner.timeoutNote(script)
                    let body = why.hasPrefix("timed out") ? String(output.dropLast(note.count)) : output
                    let shown = body.count > Owner.outputLimit ? "…" + body.suffix(Owner.outputLimit) : body
                    let lines = shown.split(whereSeparator: \.isNewline).map { "terrarium: tweak \(name)> \($0)" }
                    failAndExit(lines + ["terrarium: tweak \(name) failed (\(why))"])
                }
            }
        }
    }

    /// Runs a tweak and collects its output (both streams, in order) and exit status, through the same relay a `tweak`
    /// request uses. Blocks; call it off the main queue.
    private static func collect(_ script: Tweaks.Script, over connection: VZVirtioSocketConnection) -> (status: Int32, output: String) {
        collect(argv: script.argv, timeout: TimeInterval(script.timeout), timedOut: timeoutNote(script), over: connection)
    }

    /// Runs a command in the guest and collects its output and exit status (124 after `timedOut` on standard error when it
    /// outlasts `timeout`). Blocks; call it off the main queue.
    static func collect(argv: [String], timeout: TimeInterval, timedOut: String, over connection: VZVirtioSocketConnection) -> (status: Int32, output: String) {
        var ends: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &ends) == 0 else { return (1, "cannot run the tweak: \(String(cString: strerror(errno)))\n") }
        let reply = Reply(ends[0])
        DispatchQueue.global().async {
            HelperProtocol.relayExec(argv, over: connection, to: reply, timeout: timeout, timedOut: timedOut)
        }
        let fd = ends[1]
        defer { close(fd) }
        // The relay answers `ok` or `error: MESSAGE` and a newline, then frames.
        var line = Data()
        while let byte = readExactly(fd, 1), byte[0] != 0x0A { line.append(byte) }
        let first = String(decoding: line, as: UTF8.self)
        guard first == "ok" else { return (1, first.hasPrefix("error: ") ? String(first.dropFirst(7)) + "\n" : first + "\n") }
        var output = Data()
        while let frame = HelperProtocol.readFrame(fd) {
            switch frame.kind {
            case HelperProtocol.stdout, HelperProtocol.stderr:
                output.append(frame.payload)
            case HelperProtocol.exit:
                guard frame.payload.count == 4 else { return (1, String(decoding: output, as: UTF8.self)) }
                let code = Int32(bitPattern: UInt32(frame.payload[0]) << 24 | UInt32(frame.payload[1]) << 16 | UInt32(frame.payload[2]) << 8 | UInt32(frame.payload[3]))
                return (HelperProtocol.status(fromExit: code), String(decoding: output, as: UTF8.self))
            case HelperProtocol.error:
                output.append(frame.payload)
                return (1, String(decoding: output, as: UTF8.self))
            default:
                break
            }
        }
        return (1, String(decoding: output, as: UTF8.self) + "the helper closed the connection\n")
    }

    /// Writes the notes, then stops the VM and ends the process with status 1. The pause lets a waiting `start` read them
    /// before the VM's directory (and the log they are in) is removed.
    func failAndExit(_ notes: [String]) {
        notes.forEach(note)
        stopping = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            guard vm.canStop else { finish(1) }
            vm.stop { _ in self.finish(1) }
        }
    }
}
