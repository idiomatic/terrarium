import Foundation

/// The `--provision nocloud` recipe, for images that have no cloud-init and ask their questions on the text console (Debian's
/// `nocloud` images): it types the answers of systemd's first-boot wizard, a root password, and a login over VNC, then runs a
/// script from a volume that holds the helper. Blind timing, as measured on Debian 13: the wizard waits for a key about 30 s
/// after the VM starts, and the login prompt follows its last answer by about 20 s. Typing it twice (a login typed at a shell
/// is harmless) covers a slower boot.
extension Recipe {
    /// Installs the helper as a systemd unit, so a later boot has it too.
    static let nocloudInstall = """
    #!/bin/sh
    set -e
    install -m 0755 /mnt/terrarium-helper /usr/local/bin/terrarium-helper
    cat > /etc/systemd/system/terrarium-helper.service <<'UNIT'
    [Unit]
    Description=terrarium guest helper
    [Service]
    ExecStartPre=-/sbin/modprobe vmw_vsock_virtio_transport
    ExecStart=/usr/local/bin/terrarium-helper
    Restart=always
    [Install]
    WantedBy=multi-user.target
    UNIT
    systemctl daemon-reload
    systemctl enable --now terrarium-helper.service
    echo terrarium: the helper is installed

    """

    static func nocloud(password given: String?, in directory: URL) throws -> Plan {
        guard let helper = Embedded.helper(for: .linux) else { throw CLIError.failure("this terrarium has no Linux helper") }
        let password = given ?? randomPassword()
        if given == nil {
            let file = directory.appendingPathComponent("nocloud-password")
            try Data((password + "\n").utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            // The directory goes when the VM stops, so this is the only time it is shown.
            note("root password: \(password)")
        } else {
            note("root has the password you gave")
        }

        let staging = directory.appendingPathComponent("recipe-staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let files = try [("terrarium-helper", helper), ("install.sh", Data(nocloudInstall.utf8))].map { name, data -> URL in
            let url = staging.appendingPathComponent(name)
            try data.write(to: url)
            return url
        }
        let volume = try fatMedia(named: "recipe.img", volume: "TERRARIUM", size: "8m", entries: files.map { ($0.lastPathComponent, $0) }, in: directory)

        let login = "mountpoint -q /mnt || mount -o ro /dev/disk/by-label/TERRARIUM /mnt; sh /mnt/install.sh\n"
        // Each answer waits for its question on the screen. Debian 13 first asks for a key; Debian 14's wizard begins at the
        // timezone, so that first step is optional.
        let dialogue = [
            Expect(text: "press any key", action: .chord("return"), optional: true),
            Expect(text: "new timezone", action: .chord("return")),                    // skipped
            Expect(text: "new root password", action: .text(password + "\n")),
            Expect(text: "password again", action: .text(password + "\n")),
            Expect(text: "login:", action: .text("root\n")),
            Expect(text: "password:", action: .text(password + "\n"), settle: 4),
            Expect(text: "root@localhost", action: .text(login)),
        ]
        return Plan(kind: .linux, media: [Media(url: volume, readOnly: true)], expect: dialogue)
    }
}
