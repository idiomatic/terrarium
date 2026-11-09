import DiskImageKit
import Foundation
import Virtualization

/// What a front-end shows of an owner: a window, say. The owner calls these on the main queue.
public protocol OwnerUI: AnyObject {
    /// The VM exists and is about to start: show it.
    func show()
    /// The owner's state, a scheduled commit, or a transient status changed.
    func stateChanged()
    /// The VM was replaced by a new one over the same files (a Windows reset, the end of a macOS install).
    func vmReplaced()
    /// The guest's display changed size, in pixels.
    func guestSizeChanged(_ size: CGSize)
    /// Runs the front-end's event loop; the owner exits by itself once the VM has stopped.
    func runLoop() -> Never
}

/// Makes the front-end for an owner; `run` needs one.
public typealias OwnerUIFactory = (Owner) -> OwnerUI

/// The process that owns a running VM: boots it, serves its control socket, and removes its state when it stops.
/// It has no windows of its own; a front-end attaches through `OwnerUI`.
public final class Owner: NSObject, VZVirtualMachineDelegate {
    public let id: String
    public let directory: URL
    /// Whether a front-end shows the VM (`run`) rather than the VM running hidden (`start`).
    public let windowed: Bool
    var ui: OwnerUI?
    /// When the last `click`, `move`, `type`, or `key` finished, which a `shot` lets settle.
    var lastInput = Date.distantPast
    static let settleTime: TimeInterval = 1
    /// Why the VM ended, as `ps --deceased` tells it: set where the end is known, else the last note says.
    var endReason: String?
    /// Where a scheduled commit saved the VM, if it did.
    var savedTo: String?
    /// The helper instance that `wait` last found, which `wait --reboot` waits to see replaced.
    var helperBaseline = ""
    var info: Runtime.Info { didSet { DispatchQueue.main.async { [self] in ui?.stateChanged() } } }
    public internal(set) var vm: VZVirtualMachine!
    var control: ControlServer?
    var vnc: PrivateVNC?
    public internal(set) var stopping = false
    /// The overlay layer as it was when the VM started or was last committed.
    var committedStamp: LayerStamp?
    /// Whether a commit is copying the layer, and the reply of a stop that waits for it to finish.
    public internal(set) var committing = false
    var stopAfterCommit: ((Data) -> Void)?
    var signals: [DispatchSourceSignal] = []
    /// Where to commit (as a prefix, see `overlayTarget`) once the VM has stopped.
    public var saveOnStop: URL? { didSet { DispatchQueue.main.async { [self] in ui?.stateChanged() } } }
    /// A status a front-end shows in place of the state, such as while committing.
    public internal(set) var transient: String? { didSet { DispatchQueue.main.async { [self] in ui?.stateChanged() } } }
    var plan = Plan()
    var disk: (any StackedImage)?
    /// The guest's network MAC address, which names its lease in the host's DHCP leases.
    var guestMAC: String?
    var baseURL: URL!
    /// How many times a Windows guest has reset and been restarted.
    var resets = 0
    /// Whether the thread that follows the guest's display size is running.
    var sizeWatching = false
    /// The pending report of the guest's size to `info`; a newer size replaces it.
    var reportWork: DispatchWorkItem?
    /// When the VM last started: a guest passes through firmware modes soon after.
    public internal(set) var vmStartedAt = Date()

    let resources: Resources
    let user: String?
    let password: String?
    let acceptLicense: Bool
    let diskGB: Int?
    let commitOnStop: URL?
    /// The tweaks still to run once the helper answers (`<os>/<name>`), the first being the one running.
    var pendingTweaks: [String]

    private init(id: String, request: BootRequest, windowed: Bool) {
        self.id = id
        self.directory = Runtime.dir(id)
        self.windowed = windowed
        self.resources = request.resources
        self.user = request.user
        self.password = request.password
        self.acceptLicense = request.acceptLicense
        self.diskGB = request.diskGB
        self.commitOnStop = request.commitOnStop
        self.pendingTweaks = request.tweaks
        self.info = Runtime.Info(
            id: id, pid: getpid(), image: request.image?.name ?? request.installed?.installer ?? "-", overlay: request.overlay?.path, recipe: request.recipe?.encoded,
            windowed: windowed, state: "starting", started: Date())
    }

    /// Boots the VM and never returns: runs until the VM stops. `run` calls this with a front-end (`makeUI`); `start`'s
    /// detached child without.
    static func serve(id: String, request: BootRequest, makeUI: OwnerUIFactory?) -> Never {
        let owner = Owner(id: id, request: request, windowed: makeUI != nil)
        do {
            try owner.boot(request, makeUI: makeUI)
        } catch {
            note("terrarium: \((error as? CLIError)?.message ?? "\(error)")")
            Runtime.remove(id)
            exit(1)
        }
        if let ui = owner.ui { ui.runLoop() }
        dispatchMain()
    }

    func boot(_ request: BootRequest, makeUI: OwnerUIFactory?) throws {
        // Signals are handled from the start, off the main queue, which building media can hold for minutes: until the VM
        // exists, a signal removes the VM's directory and exits (attached media are ejected by the next startup's sweep).
        signal(SIGPIPE, SIG_IGN)
        let booted = NSLock()
        var ready = false
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            source.setEventHandler { [unowned self] in
                booted.lock()
                let running = ready
                booted.unlock()
                if running {
                    DispatchQueue.main.async { [self] in stopAndExit(reply: nil) }
                } else {
                    note("terrarium: stopped before the VM started")
                    Runtime.remove(id)
                    exit(1)
                }
            }
            source.resume()
            signals.append(source)
        }
        defer {
            booted.lock()
            ready = vm != nil
            booted.unlock()
        }
        let overlay = request.overlay
        info.state = "preparing"
        try Runtime.write(info)
        if let installed = request.installed {
            plan = try installed.plan(over: request.guest, in: directory)
        } else if let recipe = request.recipe, let image = request.image {
            plan = try recipe.plan(image: image, user: user, password: password, acceptLicense: acceptLicense, diskGB: diskGB, in: directory)
        }
        info.guest = guestOS.rawValue
        if let prefix = commitOnStop {
            try checkSaveTarget(prefix)
            saveOnStop = prefix
            note("the \(savesInstalledOverlay ? "guest" : "overlay") will be saved to \(overlayTarget(prefix).path) when the VM stops")
        }
        guard let base = plan.baseDisk ?? request.image?.url else { throw CLIError.failure("no disk to boot") }
        baseURL = base
        let disk = try openDisk(base: baseURL, overlay: overlay, directory: directory, guestLayer: plan.guestLayer)
        self.disk = disk
        committedStamp = layerStamp()
        let configuration = try makeConfiguration(disk: disk, directory: directory, plan: plan, resources: resources)
        guestMAC = macAddress(of: configuration)
        vm = VZVirtualMachine(configuration: configuration)
        vm.delegate = self
        info.state = "starting"
        control = try ControlServer(path: Runtime.socketPath(id)) { [unowned self] request, reply in
            handle(request, reply)
        }
        if let makeUI {
            ui = makeUI(self)
            ui?.show()
        }
        if let restore = plan.mac?.restoreImage {
            installMacOS(from: restore) { [self] in startVM(first: true) }
        } else {
            startVM(first: true)
        }
    }

    func startVM(first: Bool) {
        let started: (Result<Void, Error>) -> Void = { [self] result in
            switch result {
            case .success:
                vnc = PrivateVNC(vm)
                trackGuestSize()
                // Tweaks run first; the VM counts as running once they have succeeded.
                info.state = pendingTweaks.isEmpty ? "running" : "tweaking"
                vmStartedAt = Date()
                try? Runtime.write(info)
                if first {
                    if windowed {
                        print(id)
                        fflush(stdout)
                    }
                    runScript()
                    runExpect()
                    // A macOS install's tweaks wait for its helper to be installed; a failed install fails them at once.
                    if plan.mac?.account != nil {
                        installHelperInBackground { [self] error in
                            guard let error else { return runPendingTweaks() }
                            guard !pendingTweaks.isEmpty, !stopping else { return }
                            failAndExit(["terrarium: tweak \(pendingTweaks[0]) failed (the helper was not installed: \(error))"])
                        }
                    } else {
                        runPendingTweaks()
                    }
                }
            case .failure(let error):
                note("terrarium: cannot start the VM: \(error.localizedDescription)")
                finish(1)
            }
        }
        if plan.kind == .macos { startMacOS(first: first, then: started) } else { vm.start(completionHandler: started) }
    }

    /// Reads the screen every two seconds and types each of the recipe's answers once its prompt shows, until the last is typed
    /// or seven minutes have passed. Runs once, in the background.
    func runExpect() {
        let steps = plan.expect
        guard !steps.isEmpty else { return }
        DispatchQueue.global().async { [self] in
            let deadline = Date().addingTimeInterval(420)
            var next = 0
            while next < steps.count, Date() < deadline {
                Thread.sleep(forTimeInterval: 2)
                let (port, stopped) = DispatchQueue.main.sync { (vnc?.port, stopping) }
                guard !stopped else { return }
                guard let port, let png = try? Display.perform("shot", [:], port: port) else { continue }
                let screen = ScreenText.read(png: png)
                // An optional prompt that the guest never showed is passed once a later one is on the screen.
                var index = next
                while index < steps.count, !ScreenText.shows(steps[index].text, in: screen), steps[index].optional { index += 1 }
                guard index < steps.count, ScreenText.shows(steps[index].text, in: screen) else { continue }
                switch steps[index].action {
                case .chord(let chord): _ = try? Display.perform("key", ["chord": chord], port: port)
                case .text(let text): _ = try? Display.perform("type", ["text": text], port: port)
                }
                next = index + 1
                Thread.sleep(forTimeInterval: steps[index].settle)
            }
            if next < steps.count, !DispatchQueue.main.sync(execute: { stopping }) {
                note("terrarium: the console never showed \"\(steps[next].text)\"; the recipe's dialogue stopped there")
            }
        }
    }

    /// Types the recipe's keys over VNC, each at its time after the VM started. Runs once, in the background.
    func runScript() {
        let steps = plan.script
        guard !steps.isEmpty else { return }
        let begin = Date()
        DispatchQueue.global().async { [self] in
            for step in steps {
                let wait = step.at - Date().timeIntervalSince(begin)
                if wait > 0 { Thread.sleep(forTimeInterval: wait) }
                var port: UInt16?
                for _ in 0..<20 where port == nil {
                    port = DispatchQueue.main.sync { vnc?.port }
                    if port == nil { Thread.sleep(forTimeInterval: 0.5) }
                }
                guard let port, !DispatchQueue.main.sync(execute: { stopping }) else { return }
                switch step.action {
                case .chord(let chord): _ = try? Display.perform("key", ["chord": chord], port: port)
                case .text(let text): _ = try? Display.perform("type", ["text": text], port: port)
                }
            }
        }
    }

    /// A Windows guest's reset stops the VM with an error; start the guest again on the same disk, firmware variables, and media.
    func restart() {
        do {
            note("the Windows guest reset; restarting it")
            plan.script = []
            try replaceVM()
            info.state = "starting"
            startVM(first: false)
        } catch {
            note("terrarium: cannot restart the VM: \((error as? CLIError)?.message ?? "\(error)")")
            finish(1)
        }
    }

    /// A new VM over the same files, for after the old one is finished with: a Windows guest that reset, or a macOS install.
    func replaceVM() throws {
        // The VNC server holds the old VM; stop it first, or the old VM stays alive and the new one cannot start.
        vnc?.stop()
        vnc = nil
        vm = nil
        // A new stack over the same files: the old VM's attachment may still hold the previous one.
        disk = nil
        let fresh = try reopenDisk(base: baseURL, directory: directory, guestLayer: plan.guestLayer)
        disk = fresh
        let configuration = try makeConfiguration(disk: fresh, directory: directory, plan: plan, resources: resources)
        // The new network device has a new MAC address, which names the guest's lease.
        guestMAC = macAddress(of: configuration)
        vm = VZVirtualMachine(configuration: configuration)
        vm.delegate = self
        DispatchQueue.main.async { [self] in ui?.vmReplaced() }
    }

    /// Requests are one JSON object per line, `{"verb": ..., ...}`.
    func handle(_ request: String, _ reply: Reply) {
        guard let body = (try? JSONSerialization.jsonObject(with: Data(request.utf8))) as? [String: Any],
              let verb = body["verb"] as? String else {
            return reply(failed("malformed request"))
        }
        switch verb {
        case "stop":
            stopAndExit(reply: reply.callAsFunction)
        case "exec":
            guard let argv = body["argv"] as? [String], !argv.isEmpty else { return reply(failed("no command given")) }
            guard let device = vm.socketDevices.first as? VZVirtioSocketDevice else { return reply(failed("the VM has no vsock device")) }
            device.__connect(toPort: HelperProtocol.port) { connection, _ in
                guard let connection else {
                    return reply(failed("the guest's helper is not reachable (vsock port \(HelperProtocol.port)); is it running?"))
                }
                DispatchQueue.global().async { HelperProtocol.relayExec(argv, over: connection, to: reply) }
            }
        case "helper":
            guard let device = vm.socketDevices.first as? VZVirtioSocketDevice else { return reply(failed("the VM has no vsock device")) }
            device.__connect(toPort: HelperProtocol.port) { connection, _ in
                guard let connection else { return reply(failed("the guest's helper does not answer yet")) }
                DispatchQueue.global().async {
                    guard let instance = HelperProtocol.instance(over: connection) else {
                        return reply(failed("the guest's helper does not answer yet"))
                    }
                    // `baseline` set remembers the instance; get answers with the one remembered; otherwise nothing changes.
                    DispatchQueue.main.async {
                        switch body["baseline"] as? String {
                        case "set": self.helperBaseline = instance; reply(ok(Data(instance.utf8)))
                        case "get": reply(ok(Data("\(instance)\n\(self.helperBaseline)".utf8)))
                        default: reply(ok(Data(instance.utf8)))
                        }
                    }
                }
            }
        case "put", "get":
            guard let path = body["path"] as? String, !path.isEmpty else { return reply(failed("\(verb) needs a path")) }
            guard let device = vm.socketDevices.first as? VZVirtioSocketDevice else { return reply(failed("the VM has no vsock device")) }
            var message: [String: Any] = ["path": path]
            if let mode = body["mode"] as? Int { message["mode"] = mode }
            let request = (try? JSONSerialization.data(withJSONObject: message)) ?? Data()
            device.__connect(toPort: HelperProtocol.port) { connection, _ in
                guard let connection else {
                    return reply(failed("the guest's helper is not reachable (vsock port \(HelperProtocol.port)); is it running?"))
                }
                DispatchQueue.global().async {
                    if verb == "put" { HelperProtocol.relayPut(request, over: connection, to: reply) }
                    else { HelperProtocol.relayGet(request, over: connection, to: reply) }
                }
            }
        case "tweak":
            runTweak(body, reply)
        case "clipboard":
            runClipboard(body, reply)
        case "commit":
            guard let path = body["path"] as? String else { return reply(failed("commit needs a path")) }
            let prefix = URL(fileURLWithPath: path)
            if body["onStop"] as? Bool == true {
                do {
                    try checkSaveTarget(prefix)
                    saveOnStop = prefix
                    reply(ok(Data(overlayTarget(prefix).path.utf8)))
                } catch {
                    reply(failed((error as? CLIError)?.message ?? "\(error)"))
                }
            } else {
                saveOverlay(to: prefix) { result in
                    switch result {
                    case .success(let url): reply(ok(Data(url.path.utf8)))
                    case .failure(let error): reply(failed((error as? CLIError)?.message ?? "\(error)"))
                    }
                }
            }
        case "info":
            reply(ok(Data("\(info.id) \(info.state)".utf8)))
        case "logs":
            reply(ok((try? Data(contentsOf: directory.appendingPathComponent("console.log"))) ?? Data()))
        case "shot", "click", "move", "type", "key":
            guard let port = vnc?.port else { return reply(failed("the VM's display is not ready")) }
            // A guest redraws seconds after an input: a screenshot waits until a second has passed since the last one.
            let settle = verb == "shot" ? max(0, Owner.settleTime - Date().timeIntervalSince(lastInput)) : 0
            if verb != "shot" { lastInput = Date() }
            DispatchQueue.global().async { [self] in
                if settle > 0 { Thread.sleep(forTimeInterval: settle) }
                defer { if verb != "shot" { DispatchQueue.main.async { self.lastInput = Date() } } }
                do {
                    reply(ok(try Display.perform(verb, body, port: port)))
                } catch {
                    reply(failed((error as? CLIError)?.message ?? "\(error)"))
                }
            }
        default:
            reply(failed("unknown request '\(verb)'"))
        }
    }

    public func stopAndExit(reply: ((Data) -> Void)?) {
        guard !stopping else { return }
        if committing {
            // Every stop asked for meanwhile gets its answer.
            let earlier = stopAfterCommit
            stopAfterCommit = { data in
                earlier?(data)
                reply?(data)
            }
            return
        }
        stopping = true
        endReason = endReason ?? (reply == nil ? "stopped by a signal, or by closing its window" : "stopped by stop")
        // The reply comes once a scheduled commit is saved, so a stopped VM's `stop` means its commit is done too.
        guard vm.canStop else { finish(0, reply: reply) }
        vm.stop { [self] _ in finish(0, reply: reply) }
    }

    /// Ends the owner once the VM has stopped: saves a scheduled commit, then removes the VM's state. A commit that cannot be
    /// saved, or that would save a VM that stopped with an error or an install that did not finish, is not lost: the VM's
    /// files are moved to `unsaved/<id>/` in the support directory instead.
    func finish(_ code: Int32, reply: ((Data) -> Void)? = nil) -> Never {
        /// Answers a waiting `stop`, then exits.
        func end(_ status: Int32) -> Never {
            var reason = endReason ?? (lastNote.hasPrefix("terrarium: ") ? String(lastNote.dropFirst(11)) : lastNote)
            if status != 0, installFailed { reason = "the install did not finish" }
            if let savedTo { reason += "; saved to \(savedTo)" }
            Runtime.bury(info, status: status, reason: reason.isEmpty ? "ended" : reason)
            reply?(ok())
            control?.close()
            exit(status)
        }
        let installFailed = code == 0 && !installSucceeded()
        if let prefix = saveOnStop {
            // The VM has stopped, so the overlay is quiescent.
            saveOnStop = nil
            let what = savesInstalledOverlay ? "guest" : "overlay"
            if code != 0 || installFailed {
                note("terrarium: the \(installFailed ? "install did not finish" : "VM stopped with an error"), so the \(what) was not saved to \(overlayTarget(prefix).path)")
                if keepUnsaved() { end(code == 0 ? 1 : code) }
            } else {
                do {
                    let saved = try copyOverlay(to: prefix).path
                    savedTo = saved
                    note("\(what) saved to \(saved)")
                } catch {
                    note("terrarium: cannot save the \(what): \((error as? CLIError)?.message ?? "\(error)")")
                    if keepUnsaved() { end(1) }
                }
            }
        }
        Runtime.remove(id)
        end(installFailed ? 1 : code)
    }

    /// Moves the VM's files out of `vms/`, where they would be removed, and says where they are.
    private func keepUnsaved() -> Bool {
        let kept = Paths.unsaved.appendingPathComponent(id)
        do {
            try FileManager.default.createDirectory(at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: directory, to: kept)
            note("terrarium: the VM's files are kept in \(kept.path); remove them when they are no longer needed")
            return true
        } catch {
            note("terrarium: cannot keep the VM's files: \(error.localizedDescription)")
            return false
        }
    }

    /// Whether an install left word that it succeeded, read after the VM has stopped; the end of the install's log is shown
    /// when it did not. An install that leaves none, or whose medium cannot be read, counts as succeeded.
    private func installSucceeded() -> Bool {
        switch plan.installCheck {
        case nil:
            // A macOS install is unfinished until the installer's success handler has cleared the restore image.
            guard plan.mac?.restoreImage != nil else { return true }
            note("terrarium: the install did not finish")
            return false
        case .console(let line):
            let log = (try? String(contentsOf: directory.appendingPathComponent("console.log"), encoding: .utf8)) ?? ""
            if log.contains(line) { return true }
            return installFailed(log: log)
        case .file(let media, let marker, let logName):
            let mount = directory.appendingPathComponent("check", isDirectory: true)
            guard (try? FileManager.default.createDirectory(at: mount, withIntermediateDirectories: false)) != nil,
                  let handle = try? Attached.attach(media, mountPoint: mount, readOnly: true) else {
                note("terrarium: cannot read the install's result; assuming it finished")
                return true
            }
            defer { Attached.eject(handle) }
            if FileManager.default.fileExists(atPath: mount.appendingPathComponent(marker).path) { return true }
            return installFailed(log: (try? String(contentsOf: mount.appendingPathComponent(logName), encoding: .utf8)) ?? "")
        }
    }

    private func installFailed(log: String) -> Bool {
        let tail = log.split(whereSeparator: \.isNewline).suffix(15).joined(separator: "\n")
        note(tail.isEmpty ? "terrarium: the install did not finish, and it left no log" : "terrarium: the install did not finish; the end of its log:\n" + tail)
        return false
    }

    // MARK: VZVirtualMachineDelegate

    public func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        if !stopping {
            note("terrarium: the guest stopped itself")
            endReason = "the guest stopped itself (it powered off or halted)"
        }
        finish(0)
    }

    public func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        if plan.kind == .windows && !stopping && resets < 10 {
            resets += 1
            note("the VM stopped: \(error)")
            // Let this callback return before the stopped VM is replaced.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in restart() }
            return
        }
        note("terrarium: the VM stopped: \(error.localizedDescription)")
        endReason = "the VM stopped with an error: \(error.localizedDescription)"
        finish(1)
    }
}
