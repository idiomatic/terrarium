import Foundation

/// Disk images that `terrarium` attaches with `diskutil image attach` while it builds media.
/// Each attach is recorded in `attached/`, so a crash that leaves one attached is cleaned up at the next start.
enum Attached {
    struct Record: Codable {
        var device: String
        var image: String
        var diskUUID: String
        var pid: Int32
    }

    struct Handle {
        let device: String
        let record: URL

        /// Partition `n` of the attached disk, e.g. `disk14s1`.
        func partition(_ n: Int) -> String { "\(device)s\(n)" }
    }

    /// Attaches `image`, mounted at `mountPoint` when given and hidden from the Finder. `shadows` stack over it, lowest first:
    /// the last is the writable one (made if missing) unless `readOnly`, and the rest are only read.
    static func attach(_ image: URL, shadows: [URL] = [], mountPoint: URL? = nil, readOnly: Bool = false) throws -> Handle {
        var arguments = ["image", "attach", "--plist", "--nobrowse"]
        if readOnly { arguments.append("--readOnly") }
        if let mountPoint { arguments += ["--mountPoint", mountPoint.path] } else { arguments.append("--noMount") }
        let data = try runProgram("/usr/sbin/diskutil", arguments + [image.path] + shadows.flatMap { ["--shadow", $0.path] })
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let device = entities.first?["dev-entry"] as? String else {
            throw CLIError.failure("cannot read the attach result for \(image.lastPathComponent)")
        }
        let name = device.hasPrefix("/dev/") ? String(device.dropFirst(5)) : device
        let record = Record(device: name, image: image.path, diskUUID: diskUUID(name) ?? "", pid: getpid())
        try FileManager.default.createDirectory(at: Paths.attached, withIntermediateDirectories: true)
        let file = Paths.attached.appendingPathComponent("\(name).json")
        try JSONEncoder().encode(record).write(to: file)
        return Handle(device: name, record: file)
    }

    /// Ejects the disk; a busy one is unmounted by force and ejected again. One that still will not go keeps its record, so
    /// the next startup's sweep tries again.
    static func eject(_ handle: Handle) {
        if (try? runProgram("/usr/sbin/diskutil", ["eject", handle.device])) == nil {
            _ = try? runProgram("/usr/sbin/diskutil", ["unmountDisk", "force", handle.device])
            guard (try? runProgram("/usr/sbin/diskutil", ["eject", handle.device])) != nil else {
                return note("terrarium: cannot eject \(handle.device); it is ejected the next time terrarium starts")
            }
        }
        try? FileManager.default.removeItem(at: handle.record)
    }

    /// Records the disk's identity again, for a disk that was attached blank and has been partitioned since.
    static func refresh(_ handle: Handle) {
        guard let data = try? Data(contentsOf: handle.record), var record = try? JSONDecoder().decode(Record.self, from: data) else { return }
        record.diskUUID = diskUUID(handle.device) ?? ""
        try? JSONEncoder().encode(record).write(to: handle.record)
    }

    /// The first partition's GUID, which identifies the disk; a disk without one is never swept.
    private static func diskUUID(_ device: String) -> String? {
        guard let data = try? runProgram("/usr/sbin/diskutil", ["info", "-plist", "\(device)s1"]),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist["DiskUUID"] as? String
    }

    /// Ejects recorded images that are still attached and whose recording process is gone. Never touches other images.
    static func sweep() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Paths.attached, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file), let record = try? JSONDecoder().decode(Record.self, from: data) else {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            if processIsAlive(record.pid) { continue }   // still being used by a running terrarium
            // The device number can be reused, so eject only a disk that still has the recorded identity.
            if !record.diskUUID.isEmpty, diskUUID(record.device) == record.diskUUID {
                _ = try? runProgram("/usr/sbin/diskutil", ["eject", record.device])
            }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
