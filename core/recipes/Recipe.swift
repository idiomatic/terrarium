import Foundation

/// Boot-time guest setup, built on the host before the guest runs. An `--install` recipe makes a guest from an installer image;
/// a `--provision` recipe readies a live image's guest to be driven. `alpine` is one name under each flag. A recipe returns the
/// media to attach to the VM and says how the VM must be set up for it.
enum Recipe: Equatable {
    case install(String)
    case provision(String)

    /// The names each flag implements.
    static let installs = ["alpine", "macos", "windows"]
    static let provisions = ["alpine", "cloud-init", "combustion", "nocloud"]

    /// The recipe the flags ask for, if any; the two are alternatives.
    static func parse(install: String?, provision: String?) throws -> Recipe? {
        if install != nil && provision != nil { throw CLIError.usage("--install and --provision are alternatives: a VM installs or is provisioned") }
        if let install {
            guard installs.contains(install) else { throw CLIError.failure("--install \(install) is not implemented yet (available: \(installs.joined(separator: ", ")))") }
            return .install(install)
        }
        if let provision {
            guard provisions.contains(provision) else { throw CLIError.failure("--provision \(provision) is not implemented yet (available: \(provisions.joined(separator: ", ")))") }
            return .provision(provision)
        }
        return nil
    }

    /// `install:NAME` or `provision:NAME`: how the owner process's arguments and `info.json` carry it.
    var encoded: String {
        switch self {
        case .install(let name): "install:\(name)"
        case .provision(let name): "provision:\(name)"
        }
    }

    init?(encoded: String) {
        let parts = encoded.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "install": self = .install(parts[1])
        case "provision": self = .provision(parts[1])
        default: return nil
        }
    }

    var isInstall: Bool {
        if case .install = self { true } else { false }
    }

    /// The account a Windows install creates when `--user` is not given.
    static let defaultUser = "terra"

    /// Why `name` cannot be a guest account's name, or nil: letters, digits, `_` and `-`, starting with a letter or `_`, at most 20
    /// (Windows allows no more), and not one a system already has.
    static func userNameProblem(_ name: String) -> String? {
        let first = name.unicodeScalars.first.map { $0 == "_" || ($0.isASCII && $0.properties.isAlphabetic) } ?? false
        guard first, name.unicodeScalars.count <= 20,
              name.unicodeScalars.allSatisfy({ $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0) || $0 == "_" || $0 == "-") }) else {
            return "--user must be 1 to 20 letters, digits, `_`, or `-`, starting with a letter or `_`"
        }
        guard !["root", "administrator", "guest", "system", "defaultaccount"].contains(name.lowercased()) else { return "--user \(name) is a name the system already has" }
        return nil
    }

    /// The default install disk size in GB, which is also the least `--disk` takes; nil for a recipe that installs nothing.
    static func defaultDiskGB(install: String?) -> Int? {
        switch install {
        case "alpine": return alpineDiskSize
        case "windows": return windowsDiskSize
        case "macos": return macDiskSize
        default: return nil
        }
    }

    /// The most `--disk` takes: Windows' `diskpart` lists a larger disk in TB, which `install.cmd` does not look for.
    static let maxDiskGB = 1000

    /// Builds the media the recipe needs.
    func plan(image: Store.Image, user: String?, password: String?, acceptLicense: Bool, diskGB: Int?, in directory: URL) throws -> Plan {
        switch self {
        case .provision("alpine"): return Plan(media: [Media(url: try Recipe.alpineLive(in: directory), readOnly: true)])
        case .install("alpine"): return try Recipe.alpineInstall(image: image, password: password, diskGB: diskGB ?? Recipe.alpineDiskSize, in: directory)
        case .provision("cloud-init"): return Plan(media: [Media(url: try Recipe.cloudInit(in: directory), readOnly: true)])
        case .provision("combustion"): return Plan(media: [Media(url: try Recipe.combustion(in: directory), readOnly: true)])
        case .provision("nocloud"): return try Recipe.nocloud(password: password, in: directory)
        case .install("windows"): return try Recipe.windows(image: image, user: user ?? Recipe.defaultUser, password: password, acceptLicense: acceptLicense, diskGB: diskGB ?? Recipe.windowsDiskSize, in: directory)
        case .install("macos"): return try Recipe.macos(image: image, user: user, password: password, acceptLicense: acceptLicense, diskGB: diskGB ?? Recipe.macDiskSize, in: directory)
        default: throw CLIError.failure("recipe \(encoded) is not implemented yet")
        }
    }

    // MARK: --provision alpine

    static let helperService = """
    #!/sbin/openrc-run
    description="terrarium guest helper"
    command="/usr/local/bin/terrarium-helper"
    command_background=true
    pidfile="/run/terrarium-helper.pid"
    output_log="/var/log/terrarium-helper.log"
    error_log="/var/log/terrarium-helper.log"

    start_pre() {
    \tmodprobe -q vmw_vsock_virtio_transport || true
    }

    """

    /// An apkovl on a FAT volume: Alpine's initramfs applies any `*.apkovl.tar.gz` it finds on a block device at every boot.
    /// It carries the helper, an OpenRC service for it, and `.default_boot_services` so Alpine still adds its usual ones.
    private static func alpineLive(in directory: URL) throws -> URL {
        guard let helper = Embedded.helper(for: .linux) else { throw CLIError.failure("this terrarium has no Linux helper") }
        let fm = FileManager.default
        let staging = directory.appendingPathComponent("recipe-staging", isDirectory: true)
        try fm.createDirectory(at: staging.appendingPathComponent("etc/init.d"), withIntermediateDirectories: true)
        try fm.createDirectory(at: staging.appendingPathComponent("etc/runlevels/default"), withIntermediateDirectories: true)
        try fm.createDirectory(at: staging.appendingPathComponent("usr/local/bin"), withIntermediateDirectories: true)
        try Data().write(to: staging.appendingPathComponent("etc/.default_boot_services"))
        try fm.createSymbolicLink(
            atPath: staging.appendingPathComponent("etc/runlevels/default/terrarium-helper").path,
            withDestinationPath: "/etc/init.d/terrarium-helper")
        for (path, contents) in [("etc/init.d/terrarium-helper", Data(helperService.utf8)), ("usr/local/bin/terrarium-helper", helper)] {
            let url = staging.appendingPathComponent(path)
            try contents.write(to: url)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let apkovl = directory.appendingPathComponent("terrarium.apkovl.tar.gz")
        try runProgram("/usr/bin/tar", [
            "--no-mac-metadata", "--no-xattrs",
            "--uid", "0", "--gid", "0", "--uname", "root", "--gname", "root",
            "-czf", apkovl.path, "-C", staging.path, "etc", "usr",
        ])
        try fm.removeItem(at: staging)
        defer { try? fm.removeItem(at: apkovl) }
        return try fatMedia(named: "recipe.img", volume: "TERRARIUM", size: "8m", entries: [(apkovl.lastPathComponent, apkovl)], in: directory)
    }

    // MARK: cloud-init

    /// The NoCloud user-data: it writes the helper (base64), a systemd unit, and an OpenRC service, and starts the helper
    /// with whichever init the guest has (systemd, or OpenRC as in Alpine's cloud images).
    static func cloudInitUserData(helper: Data) -> String {
        let openRC = helperService.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : "      " + $0 }.joined(separator: "\n")
        return """
        #cloud-config
        write_files:
          - path: /usr/local/bin/terrarium-helper
            permissions: "0755"
            encoding: b64
            content: \(helper.base64EncodedString())
          - path: /etc/systemd/system/terrarium-helper.service
            permissions: "0644"
            content: |
              [Unit]
              Description=terrarium guest helper
              [Service]
              ExecStartPre=-/sbin/modprobe vmw_vsock_virtio_transport
              ExecStart=/usr/local/bin/terrarium-helper
              Restart=always
              [Install]
              WantedBy=multi-user.target
          - path: /usr/local/lib/terrarium-helper.initd
            permissions: "0755"
            content: |
        \(openRC)
        runcmd:
          - - sh
            - -c
            - |
              if command -v systemctl >/dev/null; then
                systemctl daemon-reload && systemctl enable --now terrarium-helper.service
              else
                # Without a CIDATA volume (a later boot), cloud-init would wait minutes on other datasources before OpenRC
                # starts the helper.
                echo 'datasource_list: [ NoCloud, None ]' > /etc/cloud/cloud.cfg.d/99-terrarium.cfg
                # Only here: systemd generates a unit from an /etc/init.d script, which can clash with the native one.
                install -m 0755 /usr/local/lib/terrarium-helper.initd /etc/init.d/terrarium-helper
                rc-update add terrarium-helper default && rc-service terrarium-helper start
              fi

        """
    }

    /// A NoCloud `cidata` FAT volume. Its user-data writes the helper and its service files and starts it.
    /// The instance ID is this VM's ID, so cloud-init treats every `start` as a new instance and runs again.
    private static func cloudInit(in directory: URL) throws -> URL {
        guard let helper = Embedded.helper(for: .linux) else { throw CLIError.failure("this terrarium has no Linux helper") }
        let userData = cloudInitUserData(helper: helper)
        let staging = directory.appendingPathComponent("recipe-staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let files = try [
            ("user-data", userData),
            ("meta-data", "instance-id: terrarium-\(directory.lastPathComponent)\nlocal-hostname: terrarium\n"),
        ].map { name, text -> URL in
            let url = staging.appendingPathComponent(name)
            try Data(text.utf8).write(to: url)
            return url
        }
        return try fatMedia(named: "recipe.img", volume: "CIDATA", size: "8m", entries: files.map { ($0.lastPathComponent, $0) }, in: directory)
    }

    // MARK: media

    /// A guest file embedded by `build.zig` (under `core/recipes/`).
    static func asset(_ section: String) throws -> Data {
        guard let data = Embedded.section(section) else { throw CLIError.failure("this terrarium has no \(section) file") }
        return data
    }

    /// The blank disk under the overlay of a guest that installs itself (Windows, macOS), a sparse file in the VM's own
    /// directory. The image cannot be the base: an installer ISO at the start of the boot disk is bootable through UDF, so
    /// the firmware runs Microsoft's boot manager before the shim, and the guest crashes at once; a macOS restore image
    /// is not a disk.
    static func blankDisk(gigabytes: Int, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("blank.img")
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CLIError.failure("cannot create \(url.path)") }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(gigabytes) << 30)
        try handle.close()
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        return url
    }

    /// Removes the shared `cache/blank-disk-<n>g.img` files that earlier versions made; a VM that still has one open keeps it.
    static func sweepRetiredBlankDisks() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Paths.cache.path)) ?? []
        for name in files where name.hasPrefix("blank-disk-") {
            try? FileManager.default.removeItem(at: Paths.cache.appendingPathComponent(name))
        }
    }

    /// A single-volume FAT disk image holding `entries` (a path inside the volume and a source), checked with `fsck_msdos`.
    static func fatMedia(named name: String, volume: String, size: String, entries: [(path: String, source: URL)], in directory: URL) throws -> URL {
        let image = directory.appendingPathComponent(name)
        try runProgram("/usr/sbin/diskutil", ["image", "create", "blank", "--fs", "MS-DOS", "--volumeName", volume, "--size", size, "--format", "RAW", image.path])
        let mountPoint = directory.appendingPathComponent("recipe-mount", isDirectory: true)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: mountPoint) }

        let attachment = try Attached.attach(image, mountPoint: mountPoint)
        defer { Attached.eject(attachment) }
        for (path, source) in entries {
            let target = mountPoint.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: target)
        }
        _ = try? runProgram("/usr/sbin/dot_clean", ["-m", mountPoint.path])
        _ = try? runProgram("/usr/bin/mdutil", ["-i", "off", mountPoint.path])
        try runProgram("/usr/sbin/diskutil", ["unmount", attachment.partition(1)])
        try runProgram("/sbin/fsck_msdos", ["-n", "/dev/r\(attachment.partition(1))"])
        return image
    }
}
