import Foundation

/// The `--provision combustion` recipe, for openSUSE's Minimal-VM, MicroOS, and Leap Micro images, which configure themselves
/// at first boot with Combustion (or Ignition) and not cloud-init. Combustion copies the `combustion` directory of a volume
/// labeled `combustion` or `COMBUSTION` (a FAT volume's label is upper case) and runs its `script` from inside it, so the
/// helper travels beside the script.
extension Recipe {
    /// Installs the helper and a systemd unit for it, in the new system (a transactional update's snapshot on MicroOS).
    static let combustionScript = """
    #!/bin/bash
    set -e
    install -m 0755 terrarium-helper /usr/bin/terrarium-helper
    cat > /etc/systemd/system/terrarium-helper.service <<'UNIT'
    [Unit]
    Description=terrarium guest helper
    [Service]
    ExecStartPre=-/sbin/modprobe vmw_vsock_virtio_transport
    ExecStart=/usr/bin/terrarium-helper
    Restart=always
    [Install]
    WantedBy=multi-user.target
    UNIT
    systemctl enable terrarium-helper.service

    """

    static func combustion(in directory: URL) throws -> URL {
        guard let helper = Embedded.helper(for: .linux) else { throw CLIError.failure("this terrarium has no Linux helper") }
        let staging = directory.appendingPathComponent("recipe-staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let files = try [("terrarium-helper", helper), ("script", Data(combustionScript.utf8))].map { name, data -> (path: String, source: URL) in
            let url = staging.appendingPathComponent(name)
            try data.write(to: url)
            return ("combustion/" + name, url)
        }
        return try fatMedia(named: "recipe.img", volume: "COMBUSTION", size: "8m", entries: files, in: directory)
    }
}
