import Foundation

/// `start` and `run`: validate the request, then hand the VM to an owner process.
public enum Launch {
    static func prepare(_ inv: Invocation) throws -> BootRequest {
        let install = inv.values["install"]
        // A name ending in `.guest` is an installed guest's path; anything else is a stored image.
        let isGuest = inv.values["image"]?.hasSuffix(GuestManifest.suffix) == true
        let recipe = try Recipe.parse(install: install, provision: inv.values["provision"])
        let resources = Resources(memoryMB: inv.values["memory"].flatMap { Int($0) }, cpus: inv.values["cpus"].flatMap { Int($0) })
        try resources.check()
        let password = inv.values["password"]
        let user = inv.values["user"]
        if let user {
            guard install == "windows" || install == "macos" else { throw CLIError.usage("--user applies to --install windows or macos") }
            if let problem = Recipe.userNameProblem(user) { throw CLIError.usage(problem) }
            guard install != "macos" || inv.flags.contains("accept-license") else {
                throw CLIError.usage("--user with --install macos needs --accept-license: the guest agrees to Apple's license while it creates the account")
            }
        }
        if install == "macos", inv.flags.contains("accept-license"), user == nil {
            throw CLIError.usage("--accept-license with --install macos needs --user NAME: the guest agrees to Apple's license while it creates the account")
        }
        if let password {
            guard install != nil || inv.values["provision"] == "nocloud" else { throw CLIError.usage("--password applies to --install, or --provision nocloud") }
            guard install != "macos" || user != nil else {
                throw CLIError.usage("--password with --install macos needs --user, which has the guest create the account")
            }
            try checkPassword(password)
            if inv.values["provision"] == "nocloud" { try checkTypable(password) }
            guard inv.values["overlay"] == nil && !isGuest else {
                throw CLIError.usage("--password sets the password when installing; an installed system keeps its own")
            }
        }
        var diskGB: Int?
        if let text = inv.values["disk"] {
            guard let least = Recipe.defaultDiskGB(install: install) else { throw CLIError.usage("--disk applies to --install") }
            guard inv.values["overlay"] == nil && !isGuest else { throw CLIError.usage("--disk sets the size when installing; an installed system keeps its own") }
            guard let size = Int(text), (least...Recipe.maxDiskGB).contains(size) else {
                throw CLIError.usage("--disk must be a whole number of GB from \(least) to \(Recipe.maxDiskGB) for --install \(install!)")
            }
            diskGB = size
        }
        let accept = inv.flags.contains("accept-license")
        if accept {
            guard install == "windows" || install == "macos" else { throw CLIError.usage("--accept-license applies to --install windows or macos") }
            guard inv.values["overlay"] == nil && !isGuest else {
                throw CLIError.usage("--accept-license applies when installing; an installed system has accepted already")
            }
        }
        let tweakNames = inv.lists["tweak"] ?? []
        if !tweakNames.isEmpty {
            guard install == nil || install == "macos" else { throw CLIError.usage("--tweak does not apply to --install \(install!); tweak the installed guest") }
            guard install == nil || user != nil else { throw CLIError.usage("--tweak with --install macos needs --user and --accept-license: the helper runs tweaks, and only an account lets terrarium install it") }
        }
        func existing(_ path: String, _ what: String) throws -> URL {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else { throw CLIError.failure("no such \(what): \(url.path)") }
            return url
        }
        // An installed guest carries its own disk and needs no image or recipe; an overlay lies over its layer.
        if isGuest, let path = inv.values["image"] {
            guard recipe == nil else { throw CLIError.usage("an installed guest boots by itself: no --install or --provision") }
            let guest = try existing(path, "guest")
            guard let manifest = GuestManifest.read(guest) else { throw CLIError.failure("\(guest.path) is not an installed guest: no \(GuestManifest.fileName)") }
            let tweaks = try Tweaks.resolve(tweakNames, for: GuestOS(rawValue: manifest.guest) ?? .linux).map(\.fullName)
            guard let path = inv.values["overlay"] else {
                return BootRequest(image: nil, overlay: guest, recipe: nil, resources: resources, tweaks: tweaks, installed: manifest)
            }
            guard let id = manifest.id else { throw CLIError.failure("\(guest.lastPathComponent) has no id: boot it and commit it again to take overlays") }
            // A path that does not exist yet starts a new layer over the guest, to be saved there by `commit`.
            let target = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
            let overlay = FileManager.default.fileExists(atPath: target.path) ? target : nil
            if let overlay {
                if GuestManifest.read(overlay) != nil { throw CLIError.usage("\(overlay.lastPathComponent) is an installed guest: boot it as the IMAGE argument") }
                try checkOverlay(overlay, guest: guest, id: id)
            }
            return BootRequest(image: nil, overlay: overlay, recipe: nil, resources: resources, tweaks: tweaks, installed: manifest, guest: guest)
        }
        var overlay: URL?
        if let path = inv.values["overlay"] {
            let url = try existing(path, "overlay")
            if GuestManifest.read(url) != nil { throw CLIError.usage("\(url.lastPathComponent) is an installed guest: boot it as the IMAGE argument") }
            overlay = url
        }
        guard let reference = inv.values["image"] else { throw CLIError.usage("missing IMAGE or PATH.guest") }
        let image = try Store.resolve(reference)
        guard !isQcow2(image.url) else {
            throw CLIError.failure("\(image.name) is a qcow2 image, which cannot boot; remove it with rmi and pull a raw image")
        }
        if Store.isRestoreImage(image) && install != "macos" {
            throw CLIError.usage("\(image.name) is a macOS restore image; install it with --install macos")
        }
        // An image that is not an installed guest is a live Linux image (Windows and macOS need `--install` or a guest);
        // a macOS install's tweaks run on the guest it makes.
        let tweaks = try Tweaks.resolve(tweakNames, for: install == "macos" ? .macos : .linux).map(\.fullName)
        guard let overlay else {
            return BootRequest(image: image, overlay: nil, recipe: recipe, resources: resources, user: user, password: password, diskGB: diskGB, acceptLicense: accept, tweaks: tweaks)
        }
        guard install == nil else {
            throw CLIError.usage("an install is saved as an installed guest: boot it as the IMAGE argument, not --overlay")
        }
        try checkOverlay(overlay, image: image)
        return BootRequest(image: image, overlay: overlay, recipe: recipe, resources: resources, password: nil, tweaks: tweaks)
    }

    /// Runs the VM in this process, in a window, until it stops.
    static func run(_ inv: Invocation) throws -> Never {
        var request = try prepare(inv)
        if let path = inv.values["commit-on-stop"] {
            // Checked now, so a bad target fails before an install starts. An install, or a guest, is saved as a guest.
            let prefix = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
            try Owner.checkSaveTarget(Owner.saveTarget(prefix, installed: request.savesGuest, image: request.saveKey))
            request.commitOnStop = prefix
        }
        guard let makeUI = Backend.windowFactory else { throw CLIError.failure("this build has no window to show") }
        // `--password -` reads the password here, once the rest is checked, in this process, so no argument of any process
        // holds it.
        if request.password == "-" {
            let password = try passwordFromInput()
            try checkPassword(password)
            if request.recipe == .provision("nocloud") { try checkTypable(password) }
            request.password = password
        }
        Owner.serve(id: try Runtime.newID(), request: request, makeUI: makeUI)
    }

    static func checkPassword(_ password: String) throws {
        guard !password.isEmpty else { throw CLIError.usage("--password must not be empty") }
        // A newline would end it early for `chpasswd` and `sudo -S`, and other control characters are no better.
        guard !password.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw CLIError.usage("--password must not contain control characters")
        }
    }

    /// The nocloud recipe types the password over VNC, so it must be US keyboard characters.
    static func checkTypable(_ password: String) throws {
        do { _ = try Input.text(password) } catch { throw CLIError.usage("--password with --provision nocloud must be US keyboard characters, which are typed at the console") }
    }

    /// One line from standard input; on a terminal, a prompt without echo. `readpassphrase(3)`, unlike `getpass(3)`, takes
    /// a buffer of any size, so a line that fills it can be refused instead of cut.
    private static func passwordFromInput() throws -> String {
        let line: String?
        if isatty(STDIN_FILENO) != 0 {
            var buffer = [CChar](repeating: 0, count: 4096)
            guard readpassphrase("Password: ", &buffer, buffer.count, RPP_ECHO_OFF | RPP_REQUIRE_TTY) != nil else {
                throw CLIError.usage("--password -: cannot read the password")
            }
            guard strlen(buffer) < buffer.count - 1 else { throw CLIError.usage("--password -: the password is too long") }
            line = String(cString: buffer)
        } else {
            line = readLine(strippingNewline: true)
        }
        guard let line else { throw CLIError.usage("--password -: no password on standard input") }
        return line
    }

    /// The detached owner process that `start` spawns. Arguments: `__serve ID IMAGE|- RECIPE|- MEMORY|- CPUS|- p:PASSWORD|- accept|- USER|- TWEAKS|- DISK|- [OVERLAY|- [GUEST]]`,
    /// the tweaks separated by commas; a plain guest is the OVERLAY, and GUEST is the guest an overlay lies over.
    public static func serve(_ args: [String]) throws -> Never {
        guard args.count >= 11 else { throw CLIError.usage("__serve takes ID IMAGE RECIPE MEMORY CPUS PASSWORD ACCEPT USER TWEAKS DISK [OVERLAY|- [GUEST]]") }
        let image = args[2] == "-" ? nil : try Store.resolve(args[2])
        let overlay = args.count > 11 && args[11] != "-" ? URL(fileURLWithPath: args[11]) : nil
        let guest = args.count > 12 ? URL(fileURLWithPath: args[12]) : nil
        let request = BootRequest(
            image: image, overlay: overlay,
            recipe: Recipe(encoded: args[3]), resources: Resources(memoryMB: Int(args[4]), cpus: Int(args[5])),
            user: args[8] == "-" ? nil : args[8],
            password: args[6].hasPrefix("p:") ? String(args[6].dropFirst(2)) : nil,
            diskGB: Int(args[10]),
            acceptLicense: args[7] == "accept", tweaks: args[9] == "-" ? [] : args[9].split(separator: ",").map(String.init), installed: (guest ?? overlay).flatMap(GuestManifest.read), guest: guest)
        Owner.serve(id: args[1], request: request, makeUI: nil)
    }

    /// Starts a detached owner process and returns the VM's ID once the VM is running.
    /// `progress` receives the owner's notes as they are written (default: the terminal's standard error).
    public static func start(_ inv: Invocation, progress: ((String) -> Void)? = nil) throws -> String {
        guard inv.values["password"] != "-" else { throw CLIError.usage("--password - reads the password from standard input, for run only: start passes it to its VM's process as an argument") }
        let request = try prepare(inv)
        let recipe = request.recipe
        let id = try Runtime.newID()
        let log = Runtime.dir(id).appendingPathComponent("serve.log")
        // The password is an argument, so `/bin/ps` shows it. A leading `p:` tells it from "no password".
        var arguments: [String] = ["__serve", id, request.image?.name ?? "-", recipe?.encoded ?? "-"]
        arguments += [request.resources.memoryMB.map(String.init) ?? "-", request.resources.cpus.map(String.init) ?? "-"]
        arguments += [request.password.map { "p:" + $0 } ?? "-", request.acceptLicense ? "accept" : "-", request.user ?? "-"]
        arguments += [request.tweaks.isEmpty ? "-" : request.tweaks.joined(separator: ","), request.diskGB.map(String.init) ?? "-"]
        // A new layer over a guest has no OVERLAY, which `-` stands for.
        let layers = request.guest.map { [request.overlay?.path ?? "-", $0.path] } ?? request.overlay.map { [$0.path] } ?? []
        let pid = try spawnDetached(arguments + layers, log: log)

        // A Windows install downloads drivers and builds media the first time, which takes minutes.
        // A parent that stays alive (the MCP server) must reap the owner when it exits, or it lingers as a zombie, which
        // `kill(pid, 0)` still reports as alive. A short-lived `start` exits first and launchd adopts the owner. The wait
        // lasts as long as the VM, so it gets a thread of its own rather than one of the global queue's.
        Thread.detachNewThread {
            var status: Int32 = 0
            waitpid(pid, &status, 0)
        }
        // Tweaks wait for the helper, which a booting guest takes minutes to start.
        let limit = recipe == .install("windows") || recipe == .install("macos") ? 12_000 : request.tweaks.isEmpty ? 600 : 7_000
        var offset = 0
        var seen = ""
        for _ in 0..<limit {
            if let info = Runtime.read(id), info.state == "running" || info.state.hasPrefix("installing") {
                // Notes written just before the state changed (an account's password, say) are still unread.
                usleep(300_000)
                if let output = try? Data(contentsOf: log), output.count > offset {
                    let fresh = Data(output[offset...])
                    if let progress { progress(String(decoding: fresh, as: UTF8.self)) } else { FileHandle.standardError.write(fresh) }
                }
                // A guest that stops itself at once (firmware finds nothing to boot) is a failure, not a VM that vanishes.
                for _ in 0..<15 {
                    usleep(100_000)
                    var status: Int32 = 0
                    if waitpid(pid, &status, WNOHANG) == pid || !processIsAlive(pid) || Runtime.read(id) == nil {
                        Runtime.remove(id)
                        throw CLIError.failure("the guest stopped itself within two seconds of starting (is the image bootable?)")
                    }
                }
                return id
            }
            // Show the owner's progress notes as they are written.
            if let output = try? Data(contentsOf: log), output.count > offset {
                let fresh = output[offset...]
                seen = String(decoding: output, as: UTF8.self)
                if let progress { progress(String(decoding: fresh, as: UTF8.self)) } else { FileHandle.standardError.write(Data(fresh)) }
                offset = output.count
            }
            var status: Int32 = 0
            if waitpid(pid, &status, WNOHANG) == pid || !processIsAlive(pid) {
                // The owner removes its directory (and this log) when it fails, so the last text read is what there is.
                let output = (try? String(contentsOf: log, encoding: .utf8)) ?? seen
                let lines = output.split(separator: "\n").map(String.init)
                let last = lines.last ?? "the VM's process exited"
                Runtime.remove(id)
                // A caller that is shown the notes as they come (the terminal) needs only the last line; one that gets them
                // separately (a progress callback) needs a failed tweak's output with the line that says it failed.
                let tweakLines = lines.reversed().prefix { $0.hasPrefix("terrarium: tweak ") }.reversed()
                if progress != nil, tweakLines.count > 1 { throw CLIError.failure(tweakLines.map { String($0.dropFirst(11)) }.joined(separator: "\n")) }
                throw CLIError.failure(last.hasPrefix("terrarium: ") ? String(last.dropFirst(11)) : last)
            }
            usleep(100_000)
        }
        // The owner is told to stop and given ten seconds, then killed; its directory goes only once it has.
        kill(pid, SIGTERM)
        for _ in 0..<100 where processIsAlive(pid) { usleep(100_000) }
        if processIsAlive(pid) {
            kill(pid, SIGKILL)
            var status: Int32 = 0
            _ = waitpid(pid, &status, 0)
        }
        Runtime.remove(id)
        throw CLIError.failure("the VM did not start in time")
    }

    /// Spawns this executable in its own session with output to `log`, so it outlives the terminal and this process.
    private static func spawnDetached(_ arguments: [String], log: URL) throws -> pid_t {
        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, log.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
        var attributes: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Only the descriptors set up above: an MCP server's pipes to other calls' programs must not stay open in a VM's process.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

        guard let executable = Bundle.main.executablePath else { throw CLIError.failure("cannot find the terrarium executable") }
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let status = posix_spawn(&pid, executable, &actions, &attributes, argv, environ)
        guard status == 0 else { throw CLIError.failure("cannot start the VM's process: \(String(cString: strerror(status)))") }
        return pid
    }

    /// Saves a VM's overlay, now or when it stops; returns the saved file's path.
    static func commit(_ inv: Invocation) throws -> String {
        let info = try Runtime.resolve(inv.values["id"]!)
        let path = URL(fileURLWithPath: (inv.values["path"]! as NSString).expandingTildeInPath).standardizedFileURL.path
        let request: [String: Any] = ["verb": "commit", "path": path, "onStop": inv.flags.contains("on-stop")]
        let line = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
        // A commit copies the whole layer, which can take minutes across volumes: wait for it.
        return String(decoding: try controlRequest(Runtime.socketPath(info.id), line, timeout: 0), as: UTF8.self)
    }

    static func stop(_ reference: String) throws -> String {
        let info = try Runtime.resolve(reference)
        do {
            // The reply waits for a scheduled commit, which can take minutes to copy.
            _ = try controlRequest(Runtime.socketPath(info.id), #"{"verb":"stop"}"#, timeout: 0)
        } catch {
            kill(info.pid, SIGTERM)
        }
        for _ in 0..<100 {
            if !processIsAlive(info.pid) { return info.id }
            usleep(100_000)
        }
        throw CLIError.failure("VM \(info.id) did not stop")
    }
}
