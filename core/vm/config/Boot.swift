import DiskImageKit
import Foundation
import Virtualization

/// A layer's identity files (a macOS guest's auxiliary storage, hardware model, and machine identifier) are the VM's own
/// copies, cloned from the bundle it started from; the layer's files that are not identity (the manifest, `chain/`, and the
/// delta) stay behind.
private func cloneIdentity(of source: URL?, into directory: URL) throws {
    guard let source else { return }
    for name in try FileManager.default.contentsOfDirectory(atPath: source.path)
    where name != LayerManifest.fileName && name != LayerManifest.chainDirectory && name != LayerManifest.deltaFile
        && !FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
        try Pull.cloneOrCopy(source.appendingPathComponent(name), to: directory.appendingPathComponent(name))
    }
}

/// The VM's disk: the read-only base, the chain of ancestors' layers (root first) over it, and this VM's own delta last.
/// With `keepDelta`, the delta starts as a copy of that layer's own (a clone on its volume), which is never written itself.
func openDisk(base url: URL, chain: [URL], keepDelta: URL?, source: URL?, directory: URL) throws -> any StackedImage {
    var base: DiskImage = try DiskImage(opening: .open(url: url, mode: .readOnly))
    for layer in chain { base = try base.appending(DiskImage(opening: .open(url: layer, mode: .readOnly))) }
    try cloneIdentity(of: source, into: directory)
    let delta = directory.appendingPathComponent(MacFiles.layer)
    guard let keepDelta else { return try base.appending(.asifLayer(url: delta, type: .overlay)) }
    try Pull.cloneOrCopy(keepDelta, to: delta)
    return try base.appending(try DiskImage(opening: .open(url: delta, mode: .readWrite)))
}

/// Memory and CPU choices from `--memory` and `--cpus`; nil takes the default for the guest.
struct Resources {
    var memoryMB: Int?
    var cpus: Int?

    /// Rejects values outside what Virtualization allows on this Mac, with the allowed range.
    func check() throws {
        let memory = VZVirtualMachineConfiguration.self
        if let memoryMB {
            let low = Int(memory.minimumAllowedMemorySize >> 20), high = Int(memory.maximumAllowedMemorySize >> 20)
            guard (low...high).contains(memoryMB) else { throw CLIError.usage("--memory: \(memoryMB) MiB is outside \(low) to \(high) MiB") }
        }
        if let cpus {
            let low = memory.minimumAllowedCPUCount, high = memory.maximumAllowedCPUCount
            guard (low...high).contains(cpus) else { throw CLIError.usage("--cpus: \(cpus) is outside \(low) to \(high)") }
        }
    }
}

/// Opens an existing VM's disk again: the base under the layer already in `directory`.
func reopenDisk(base url: URL, chain: [URL], directory: URL) throws -> any StackedImage {
    var base: DiskImage = try DiskImage(opening: .open(url: url, mode: .readOnly))
    for layer in chain { base = try base.appending(DiskImage(opening: .open(url: layer, mode: .readOnly))) }
    let delta = try DiskImage(opening: .open(url: directory.appendingPathComponent(MacFiles.layer), mode: .readWrite))
    return try base.appending(delta)
}

enum GuestKind {
    case linux
    case windows
    case macos
}

/// A disk image attached to a VM besides its boot disk.
struct Media {
    let url: URL
    let readOnly: Bool
}

/// One answer of a console dialogue: typed when the screen shows `text`. The steps run in order.
struct Expect {
    /// Lowercase, a fragment of what the prompt says, as `ScreenText.read` returns it.
    let text: String
    let action: KeyStep.Action
    /// Skipped if a later step's prompt shows first (a screen that some images do not show).
    var optional = false
    /// Seconds to let the guest take the answer before the next look.
    var settle = 2.0
}

/// What a recipe asks of the VM: the kind of guest, extra media, a base disk other than the image, and keys to type once it runs.
struct Plan {
    var kind: GuestKind = .linux
    var media: [Media] = []
    var baseDisk: URL?
    var script: [KeyStep] = []
    /// Answers typed as the screen asks for them, from the start of the VM until the last is typed.
    var expect: [Expect] = []
    var mac: MacPlan?
    /// Boots the media before the disk (an installer ISO, with the blank disk to install onto last).
    var mediaFirst = false
    /// An `--install` recipe: what it leaves is saved as a root layer, `diskGB` big.
    var installed = false
    var diskGB = 0
    /// The files under the VM's own delta, read-only, root first: an image when the chain begins at one (also `baseDisk`), then
    /// the ancestors' layers. `commit` clones them into the layer it saves.
    var chain: [ChainFile] = []
    /// `--clone` or `--continue`: the layer's own delta, which the VM's starts as a clone of.
    var keepDelta: URL?
    /// The layer the VM started from, whose identity files (macOS) the VM takes.
    var source: URL?
    /// Where the VM takes the layer's identity files from: a snapshot of `source`, or `source` itself.
    var identity: URL?
    /// What an install leaves only once it has succeeded; without it, the stopped VM is not saved as an installed guest.
    var installCheck: InstallCheck?
}

/// Where an install leaves word that it succeeded.
enum InstallCheck {
    /// The file `marker` on the FAT volume of `media`, with the install's `log` beside it either way.
    case file(media: URL, marker: String, log: String)
    /// A line the install prints on the serial console, which the VM's `console.log` keeps.
    case console(String)
}

/// One step of a script typed over VNC, `at` seconds after the VM started.
struct KeyStep {
    enum Action {
        case chord(String)
        case text(String)
    }
    let at: Double
    let action: Action
}

/// The EFI variable store, created on first use. Windows gets a new one at every boot: it registers its own boot entry,
/// and with that entry the firmware runs Microsoft's boot manager directly and skips the shim, which leaves it no display.
private func variableStore(_ directory: URL, fresh: Bool) throws -> VZEFIVariableStore {
    let url = directory.appendingPathComponent("nvram")
    if fresh { try? FileManager.default.removeItem(at: url) }
    return FileManager.default.fileExists(atPath: url.path)
        ? VZEFIVariableStore(url: url)
        : try VZEFIVariableStore(creatingVariableStoreAt: url)
}

/// An EFI-booting guest with a display, input, NAT, vsock, and a console log. Linux and other EFI disks boot from
/// virtio block; Windows from NVMe, with its media on USB and the platform's performance monitoring unit on.
func makeConfiguration(disk: DiskImage, directory: URL, plan: Plan = Plan(), resources: Resources = Resources()) throws -> VZVirtualMachineConfiguration {
    if plan.kind == .macos { return try makeMacConfiguration(disk: disk, directory: directory, plan: plan, resources: resources) }
    let config = VZVirtualMachineConfiguration()
    let windows = plan.kind == .windows
    config.cpuCount = resources.cpus ?? max(2, min(4, ProcessInfo.processInfo.activeProcessorCount))
    config.memorySize = UInt64(resources.memoryMB ?? (windows ? 8192 : 4096)) << 20

    let platform = VZGenericPlatformConfiguration()
    if windows { PrivatePlatform.enablePerformanceMonitoring(platform) }
    config.platform = platform

    let loader = VZEFIBootLoader()
    loader.variableStore = try variableStore(directory, fresh: windows)
    config.bootLoader = loader

    let attachment = try VZDiskImageStorageDeviceAttachment(diskImage: disk)
    if windows {
        // Media first, then the disk: the firmware tries the shim on the first one.
        config.usbControllers = [VZXHCIControllerConfiguration()]
        config.storageDevices = try plan.media.map {
            VZUSBMassStorageDeviceConfiguration(attachment: try VZDiskImageStorageDeviceAttachment(url: $0.url, readOnly: $0.readOnly))
        } + [VZNVMExpressControllerDeviceConfiguration(attachment: attachment)]
    } else {
        // A recipe's media come after the boot disk, read-only; an installer's come first, so the firmware boots it.
        let media = try plan.media.map { VZVirtioBlockDeviceConfiguration(attachment: try VZDiskImageStorageDeviceAttachment(url: $0.url, readOnly: $0.readOnly)) }
        let disk = VZVirtioBlockDeviceConfiguration(attachment: attachment)
        config.storageDevices = plan.mediaFirst ? media + [disk] : [disk] + media
    }

    let graphics = VZVirtioGraphicsDeviceConfiguration()
    graphics.scanouts = [VZVirtioGraphicsScanoutConfiguration(widthInPixels: 1280, heightInPixels: 800)]
    config.graphicsDevices = [graphics]
    config.keyboards = [VZUSBKeyboardConfiguration()]
    config.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]

    let network = VZVirtioNetworkDeviceConfiguration()
    network.attachment = VZNATNetworkDeviceAttachment()
    config.networkDevices = [network]
    config.socketDevices = [VZVirtioSocketDeviceConfiguration()]
    config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

    let log = directory.appendingPathComponent("console.log")
    if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
    let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
    // Appended to: a Windows guest that resets gets a new VM over the same directory, and its earlier boots stay in the log.
    let handle = try FileHandle(forWritingTo: log)
    try handle.seekToEnd()
    serial.attachment = VZFileHandleSerialPortAttachment(fileHandleForReading: nil, fileHandleForWriting: handle)
    config.serialPorts = [serial]

    try config.validate()
    return config
}

extension Plan {
    /// The chain's layer files, which stack over the base (an image at the chain's start is the base itself).
    var layerURLs: [URL] { chain.filter { !$0.isImage }.map(\.url) }
}
