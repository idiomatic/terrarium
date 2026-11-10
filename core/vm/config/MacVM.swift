import DiskImageKit
import Foundation
import Virtualization

/// The files that make a macOS guest one machine. They live in `vms/<id>/` beside the VM's delta, and a saved macOS layer holds them.
enum MacFiles {
    /// The VM's delta in `vms/<id>/`, whatever the guest; a saved layer calls it `delta.asif` too.
    static let layer = LayerManifest.deltaFile
    static let auxiliaryStorage = "aux"
    static let hardwareModel = "hardware-model"
    static let machineIdentifier = "machine-id"
    static let all = [layer, auxiliaryStorage, hardwareModel, machineIdentifier]
}

/// What `--install macos` asks of the VM besides the guest kind.
struct MacPlan {
    /// The restore image to install from; nil boots an installed system.
    var restoreImage: URL?
    /// The account the guest creates on its first boot; nil leaves Setup Assistant to the caller.
    var account: Account?
    /// The smallest CPU count and memory the restore image supports (zero when unknown).
    var minimumCPUs = 0
    var minimumMemoryMB = 0

    struct Account {
        let username: String
        let password: String
    }
}

/// A macOS guest: Apple's platform, boot loader, graphics, and input, with the saved identity and auxiliary storage.
func makeMacConfiguration(disk: DiskImage, directory: URL, plan: Plan, resources: Resources) throws -> VZVirtualMachineConfiguration {
    let config = VZVirtualMachineConfiguration()
    let minimum = plan.mac ?? MacPlan()
    if let cpus = resources.cpus, cpus < minimum.minimumCPUs {
        throw CLIError.usage("--cpus: this macOS needs at least \(minimum.minimumCPUs)")
    }
    if let memory = resources.memoryMB, memory < minimum.minimumMemoryMB {
        throw CLIError.usage("--memory: this macOS needs at least \(minimum.minimumMemoryMB) MiB")
    }
    config.cpuCount = resources.cpus ?? max(minimum.minimumCPUs, 2, min(4, ProcessInfo.processInfo.activeProcessorCount))
    config.memorySize = UInt64(resources.memoryMB ?? max(minimum.minimumMemoryMB, 8192)) << 20

    guard let model = VZMacHardwareModel(dataRepresentation: try Data(contentsOf: directory.appendingPathComponent(MacFiles.hardwareModel))),
          let identifier = VZMacMachineIdentifier(dataRepresentation: try Data(contentsOf: directory.appendingPathComponent(MacFiles.machineIdentifier))) else {
        throw CLIError.failure("the macOS guest's identity files are unreadable")
    }
    let platform = VZMacPlatformConfiguration()
    platform.hardwareModel = model
    platform.machineIdentifier = identifier
    platform.auxiliaryStorage = VZMacAuxiliaryStorage(url: directory.appendingPathComponent(MacFiles.auxiliaryStorage))
    config.platform = platform
    config.bootLoader = VZMacOSBootLoader()

    config.storageDevices = [VZVirtioBlockDeviceConfiguration(attachment: try VZDiskImageStorageDeviceAttachment(diskImage: disk))]

    let graphics = VZMacGraphicsDeviceConfiguration()
    graphics.displays = [VZMacGraphicsDisplayConfiguration(widthInPixels: 1280, heightInPixels: 800, pixelsPerInch: 80)]
    config.graphicsDevices = [graphics]
    config.keyboards = [VZMacKeyboardConfiguration(), VZUSBKeyboardConfiguration()]
    config.pointingDevices = [VZMacTrackpadConfiguration(), VZUSBScreenCoordinatePointingDeviceConfiguration()]

    let network = VZVirtioNetworkDeviceConfiguration()
    network.attachment = VZNATNetworkDeviceAttachment()
    config.networkDevices = [network]
    config.socketDevices = [VZVirtioSocketDeviceConfiguration()]
    config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

    // macOS has no serial console; `logs` still reads this file.
    let log = directory.appendingPathComponent("console.log")
    if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }

    try config.validate()
    return config
}

/// The MAC address of the guest's network device, which names its lease in the host's DHCP leases.
func macAddress(of config: VZVirtualMachineConfiguration) -> String? {
    (config.networkDevices.first as? VZVirtioNetworkDeviceConfiguration)?.macAddress.string
}
