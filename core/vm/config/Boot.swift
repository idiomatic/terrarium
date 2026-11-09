import DiskImageKit
import Foundation
import Virtualization

/// An `<imagehash>` is the last 16 hex digits of a stored image name and of an overlay's `PATH-<imagehash>.overlay`.
private func trailingHash(_ name: String, suffix: String) -> String? {
    guard name.hasSuffix(suffix) else { return nil }
    let stem = String(name.dropLast(suffix.count))
    guard stem.count > 17, stem[stem.index(stem.endIndex, offsetBy: -17)] == "-" else { return nil }
    let hash = String(stem.suffix(16))
    return hash.allSatisfy { $0.isHexDigit && !$0.isUppercase } ? hash : nil
}

/// Rejects an overlay named for a different image; a name without a hash skips the check.
func checkOverlay(_ overlay: URL, image: Store.Image) throws {
    guard let wanted = trailingHash(overlay.lastPathComponent, suffix: ".overlay") else { return }
    guard wanted == trailingHash(image.name, suffix: "") else {
        throw CLIError.failure("overlay \(overlay.lastPathComponent) belongs to another image than \(image.name)")
    }
}

/// Rejects an overlay named for a different guest than the one with manifest `id`; a name without an ID skips the check.
func checkOverlay(_ overlay: URL, guest: URL, id: String) throws {
    guard let wanted = trailingHash(overlay.lastPathComponent, suffix: ".overlay") else { return }
    guard wanted == id else {
        throw CLIError.failure("overlay \(overlay.lastPathComponent) belongs to another guest than \(guest.lastPathComponent)")
    }
}

/// A macOS guest's identity files stay with the guest; an overlay over it carries only what the VM changes.
private func cloneGuestFiles(of guestLayer: URL?, into directory: URL) throws {
    guard let guest = guestLayer?.deletingLastPathComponent() else { return }
    for name in try FileManager.default.contentsOfDirectory(atPath: guest.path)
    where name != GuestManifest.fileName && name != MacFiles.layer && !FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
        guard clonefile(guest.appendingPathComponent(name).path, directory.appendingPathComponent(name).path, 0) == 0 else {
            throw CLIError.failure("cannot copy guest: \(String(cString: strerror(errno)))")
        }
    }
}

/// The VM's disk: the read-only base image under this VM's own overlay layer.
/// A given overlay is cloned with `clonefile(2)` first, never written itself.
/// With `guestLayer`, an installed guest's layer sits read-only between them, and the overlay is a layer over it.
func openDisk(base url: URL, overlay: URL?, directory: URL, guestLayer: URL? = nil) throws -> any StackedImage {
    var base: DiskImage = try DiskImage(opening: .open(url: url, mode: .readOnly))
    if let guestLayer { base = try base.appending(DiskImage(opening: .open(url: guestLayer, mode: .readOnly))) }
    let layer = directory.appendingPathComponent("overlay.asif")
    guard let overlay else {
        try cloneGuestFiles(of: guestLayer, into: directory)
        return try base.appending(.asifLayer(url: layer, type: .overlay))
    }
    // An installed overlay is a directory: the layer, any identity files, and the manifest, which stays behind.
    var isDirectory: ObjCBool = false
    FileManager.default.fileExists(atPath: overlay.path, isDirectory: &isDirectory)
    let names = isDirectory.boolValue
        ? try FileManager.default.contentsOfDirectory(atPath: overlay.path).filter { $0 != GuestManifest.fileName }
        : [MacFiles.layer]
    for name in names {
        let source = isDirectory.boolValue ? overlay.appendingPathComponent(name) : overlay
        guard clonefile(source.path, directory.appendingPathComponent(name).path, 0) == 0 else {
            throw CLIError.failure("cannot copy overlay: \(String(cString: strerror(errno)))")
        }
    }
    try cloneGuestFiles(of: guestLayer, into: directory)
    return try base.appending(try DiskImage(opening: .open(url: layer, mode: .readWrite)))
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
func reopenDisk(base url: URL, directory: URL, guestLayer: URL? = nil) throws -> any StackedImage {
    var base: DiskImage = try DiskImage(opening: .open(url: url, mode: .readOnly))
    if let guestLayer { base = try base.appending(DiskImage(opening: .open(url: guestLayer, mode: .readOnly))) }
    let layer = try DiskImage(opening: .open(url: directory.appendingPathComponent("overlay.asif"), mode: .readWrite))
    return try base.appending(layer)
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

/// What a recipe asks of the VM: the kind of guest, extra media, a base disk other than the image, and keys to type once it runs.
struct Plan {
    var kind: GuestKind = .linux
    var media: [Media] = []
    var baseDisk: URL?
    var script: [KeyStep] = []
    var mac: MacPlan?
    /// Boots the media before the disk (an installer ISO, with the blank disk to install onto last).
    var mediaFirst = false
    /// An `--install` recipe: what it leaves is saved as an installed guest, `diskGB` big.
    var installed = false
    var diskGB = 0
    /// An overlay over an installed guest: that guest's layer (read-only, under the VM's own) and its manifest `id`.
    var guestLayer: URL?
    var guestID: String?
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
