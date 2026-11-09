import Foundation

/// The virtio-win drivers `--install windows` installs.
extension Recipe {
    /// The virtio-win drivers (display, network, vsock), pinned.
    static let virtioWinURL = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.302-1/virtio-win-0.1.302.iso"
    static let virtioWinSHA256 = "303f7ae40dad495d6ae474fdc571df58958a4dbc5c37a522d80f9a203867949d"
    static let virtioDrivers = ["viogpudo", "NetKVM", "viosock"]

    /// The extracted `viogpudo`, `NetKVM`, and `viosock` drivers for Windows 11 on ARM64, downloaded once.
    static func virtioDriverDirectory() throws -> URL {
        let fm = FileManager.default
        let target = Paths.cache.appendingPathComponent("virtio-win-\(virtioWinSHA256.prefix(12))", isDirectory: true)
        if virtioDrivers.allSatisfy({ fm.fileExists(atPath: target.appendingPathComponent($0).path) }) { return target }
        try fm.createDirectory(at: Paths.cache, withIntermediateDirectories: true)

        let iso = Paths.cache.appendingPathComponent("virtio-win.iso.partial.\(getpid())")
        defer { try? fm.removeItem(at: iso) }
        note("downloading the virtio-win drivers")
        try Pull.download(URL(string: virtioWinURL)!, to: iso)
        guard try hashFile(iso, suffix: "") == virtioWinSHA256 else { throw CLIError.failure("the virtio-win download does not match its pinned SHA-256") }

        let mount = Paths.cache.appendingPathComponent("virtio-mount-\(getpid())", isDirectory: true)
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: mount) }
        let partial = Paths.cache.appendingPathComponent("virtio-win-extract.partial.\(getpid())", isDirectory: true)
        defer { try? fm.removeItem(at: partial) }
        try? fm.removeItem(at: partial)
        let attachment = try Attached.attach(iso, mountPoint: mount, readOnly: true)
        defer { Attached.eject(attachment) }
        for driver in virtioDrivers {
            let source = mount.appendingPathComponent("\(driver)/w11/ARM64")
            let destination = partial.appendingPathComponent(driver)
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            for name in try fm.contentsOfDirectory(atPath: source.path) where !name.hasSuffix(".pdb") {
                try fm.copyItem(at: source.appendingPathComponent(name), to: destination.appendingPathComponent(name))
            }
        }
        try? fm.removeItem(at: target)
        try fm.moveItem(at: partial, to: target)
        return target
    }
}
