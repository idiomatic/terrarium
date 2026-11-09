import Foundation

/// The `--install alpine` recipe: boots the ISO, and an apkovl hook installs Alpine onto a blank disk with `setup-alpine`, adds
/// the helper and the root password, and powers off. The installed system is saved with `commit --on-stop`, as an installed
/// guest that boots from its own disk.
extension Recipe {
    /// The install target's default size in GB.
    static let alpineDiskSize = 4

    static func alpineInstall(image: Store.Image, password given: String?, diskGB: Int, in directory: URL) throws -> Plan {
        guard let helper = Embedded.helper(for: .linux) else { throw CLIError.failure("this terrarium has no Linux helper") }
        let password = given ?? randomPassword()
        if given == nil {
            let file = directory.appendingPathComponent("alpine-password")
            try Data((password + "\n").utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            // The directory goes when the VM stops, so this is the only time it is shown.
            note("Alpine account: root, password \(password)")
        } else {
            note("Alpine account: root, with the password you gave")
        }

        let fm = FileManager.default
        let staging = directory.appendingPathComponent("recipe-staging", isDirectory: true)
        try fm.createDirectory(at: staging.appendingPathComponent("etc/local.d"), withIntermediateDirectories: true)
        try fm.createDirectory(at: staging.appendingPathComponent("etc/terrarium"), withIntermediateDirectories: true)
        try fm.createDirectory(at: staging.appendingPathComponent("etc/runlevels/default"), withIntermediateDirectories: true)
        try Data().write(to: staging.appendingPathComponent("etc/.default_boot_services"))
        try fm.createSymbolicLink(
            atPath: staging.appendingPathComponent("etc/runlevels/default/local").path,
            withDestinationPath: "/etc/init.d/local")
        let files: [(String, Data, Int)] = [
            ("etc/local.d/terrarium-install.start", try asset("alp-start"), 0o755),
            ("etc/terrarium/answers", try asset("alp-answers"), 0o644),
            ("etc/terrarium/terrarium-helper", helper, 0o755),
            ("etc/terrarium/terrarium-helper.initd", Data(helperService.utf8), 0o755),
            ("etc/terrarium/password", Data((password + "\n").utf8), 0o600),
        ]
        for (path, contents, mode) in files {
            let url = staging.appendingPathComponent(path)
            try contents.write(to: url)
            try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        }
        let apkovl = directory.appendingPathComponent("terrarium.apkovl.tar.gz")
        try runProgram("/usr/bin/tar", [
            "--no-mac-metadata", "--no-xattrs",
            "--uid", "0", "--gid", "0", "--uname", "root", "--gname", "root",
            "-czf", apkovl.path, "-C", staging.path, "etc",
        ])
        try fm.removeItem(at: staging)
        defer { try? fm.removeItem(at: apkovl) }
        let volume = try fatMedia(named: "recipe.img", volume: "TERRARIUM", size: "8m", entries: [(apkovl.lastPathComponent, apkovl)], in: directory)

        // The ISO boots first, the recipe's volume is read by Alpine's initramfs, and the target is the last disk.
        return Plan(
            kind: .linux, media: [Media(url: image.url, readOnly: true), Media(url: volume, readOnly: true)],
            baseDisk: try blankDisk(gigabytes: diskGB, in: directory), mediaFirst: true, installed: true, diskGB: diskGB,
            installCheck: .console("terrarium: Alpine is installed"))
    }
}
