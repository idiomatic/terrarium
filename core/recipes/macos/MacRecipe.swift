import Foundation
import Virtualization

/// The `--install macos` recipe. It installs from the restore image (an IPSW, stored as is): the VM's process
/// runs Apple's installer onto a blank disk, then boots the system once with first-boot provisioning (an account, automatic
/// login, Remote Login) and installs the helper over SSH. The saved guest boots by its path.
extension Recipe {
    /// The install target's default size in GB.
    static let macDiskSize = 40

    static func macos(image: Store.Image, user: String?, password given: String?, acceptLicense: Bool, diskGB: Int, in directory: URL) throws -> Plan {
        guard Store.isRestoreImage(image) else { throw CLIError.failure("\(image.name) is not a macOS restore image (an IPSW)") }
        let base = try blankDisk(gigabytes: diskGB, in: directory)
        // Virtualization takes a restore image by its `.ipsw` extension; the store's files end in `.img`, so the VM gets a clone
        // (free on the store's APFS volume) under the right name.
        let ipsw = directory.appendingPathComponent("restore.ipsw")
        try Pull.cloneOrCopy(image.url, to: ipsw)
        note("reading the restore image")
        let restore = try loadRestoreImage(ipsw)
        guard let requirements = restore.mostFeaturefulSupportedConfiguration else {
            throw CLIError.failure("this Mac cannot run the macOS in \(image.name)")
        }
        try requirements.hardwareModel.dataRepresentation.write(to: directory.appendingPathComponent(MacFiles.hardwareModel))
        try VZMacMachineIdentifier().dataRepresentation.write(to: directory.appendingPathComponent(MacFiles.machineIdentifier))
        _ = try VZMacAuxiliaryStorage(
            creatingStorageAt: directory.appendingPathComponent(MacFiles.auxiliaryStorage),
            hardwareModel: requirements.hardwareModel, options: [])

        var mac = MacPlan(
            restoreImage: ipsw,
            minimumCPUs: requirements.minimumSupportedCPUCount,
            minimumMemoryMB: Int(requirements.minimumSupportedMemorySize >> 20))
        if acceptLicense, let user {
            note("--accept-license: accepting the macOS Software License Agreement (https://www.apple.com/legal/sla/) for this install")
            let password = given ?? randomPassword()
            if given == nil {
                let file = directory.appendingPathComponent("macos-password")
                try Data((password + "\n").utf8).write(to: file)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                // The directory goes when the VM stops, so this is the only time it is shown.
                note("macOS account: \(user), password \(password) (automatic login and Remote Login are on)")
            } else {
                note("macOS account: \(user), with the password you gave (automatic login and Remote Login are on)")
            }
            mac.account = MacPlan.Account(username: user, password: password)
        } else {
            note("macOS will stop at Setup Assistant, where you agree to Apple's license (shot, then click and type); the helper is not installed without --user and --accept-license")
        }
        return Plan(kind: .macos, baseDisk: base, mac: mac, installed: true, diskGB: diskGB)
    }

    /// Loads a restore image's description. The completion may need the main queue, so a main-thread caller keeps it running.
    static func loadRestoreImage(_ url: URL) throws -> VZMacOSRestoreImage {
        nonisolated(unsafe) var result: Result<VZMacOSRestoreImage, Error>?
        VZMacOSRestoreImage.load(from: url) { loaded in result = loaded }
        while result == nil { RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05)) }
        switch result! {
        case .success(let image): return image
        case .failure(let error): throw CLIError.failure("cannot read the restore image: \(error.localizedDescription)")
        }
    }

    static func randomPassword() -> String {
        let alphabet = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<16).map { _ in alphabet.randomElement()! })
    }
}
