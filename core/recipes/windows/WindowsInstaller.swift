import Foundation

/// The Windows installer media: the ISO's tree on FAT32 and `install.wim` on exFAT.
extension Recipe {
    /// Bump when the installer media's layout changes, so cached media is rebuilt.
    static let installerMediaRecipe = 1

    /// A GPT disk with a FAT32 partition for the ISO's tree and an exFAT one for `install.wim`, which is over FAT32's limit:
    /// WinPE cannot read the ISO's UDF from a disk device. Built once per image, then cached.
    static func installerMedia(for image: Store.Image) throws -> (url: URL, index: Int) {
        let fm = FileManager.default
        try fm.createDirectory(at: Paths.cache, withIntermediateDirectories: true)
        let final = Paths.cache.appendingPathComponent("windows-\(image.name)-r\(installerMediaRecipe).img")
        let indexFile = URL(fileURLWithPath: final.path + ".index")
        if fm.fileExists(atPath: final.path), let text = try? String(contentsOf: indexFile, encoding: .utf8),
           let index = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return (final, index)
        }

        note("building the Windows installer media (once per image; it takes a few minutes)")
        let work = Paths.cache.appendingPathComponent("build-\(getpid())", isDirectory: true)
        let mounts = ["iso", "boot", "inst"].map { work.appendingPathComponent($0, isDirectory: true) }
        for mount in mounts { try fm.createDirectory(at: mount, withIntermediateDirectories: true) }
        defer { try? fm.removeItem(at: work) }
        let partial = URL(fileURLWithPath: final.path + ".partial.\(getpid())")
        defer { try? fm.removeItem(at: partial) }

        let isoAttachment = try Attached.attach(image.url, mountPoint: mounts[0], readOnly: true)
        defer { Attached.eject(isoAttachment) }
        let wim = mounts[0].appendingPathComponent("sources/install.wim")
        guard fm.fileExists(atPath: wim.path) else { throw CLIError.failure("\(image.name) is not a Windows installer image: no sources/install.wim") }
        let index = try wimEditionIndex(wim)
        let wimBytes = (try fm.attributesOfItem(atPath: wim.path)[.size] as? Int) ?? 0
        let treeBytes = try treeSize(mounts[0], excluding: wim)

        let megabyte = 1 << 20
        let bootMB = treeBytes * 115 / 100 / megabyte + 64
        let wimMB = wimBytes * 102 / 100 / megabyte + 64
        guard fm.createFile(atPath: partial.path, contents: nil) else { throw CLIError.failure("cannot create \(partial.path)") }
        let handle = try FileHandle(forWritingTo: partial)
        try handle.truncate(atOffset: UInt64((bootMB + wimMB + 16) * megabyte))
        try handle.close()

        let media = try Attached.attach(partial)
        defer { Attached.eject(media) }
        try runProgram("/usr/sbin/diskutil", ["partitionDisk", media.device, "GPT", "FAT32", "WINBOOT", "\(bootMB)m", "ExFAT", "WININST", "R"])
        // Attached blank, the disk had no identity to record; now it does, so a crash from here on is swept.
        Attached.refresh(media)
        // partitionDisk mounts under /Volumes; remount privately so no volume name can collide.
        for (partition, mount) in [(media.partition(2), mounts[1]), (media.partition(3), mounts[2])] {
            try runProgram("/usr/sbin/diskutil", ["unmount", partition])
            try runProgram("/usr/sbin/diskutil", ["mount", "-mountPoint", mount.path, partition])
        }

        note("copying the installer files")
        try runProgram("/usr/bin/rsync", ["-rt", "--exclude", "install.wim", mounts[0].path + "/", mounts[1].path + "/"])
        try fm.createDirectory(at: mounts[2].appendingPathComponent("sources"), withIntermediateDirectories: true)
        try fm.copyItem(at: wim, to: mounts[2].appendingPathComponent("sources/install.wim"))
        for mount in [mounts[1], mounts[2]] {
            _ = try? runProgram("/usr/sbin/dot_clean", ["-m", mount.path])
            _ = try? runProgram("/usr/bin/mdutil", ["-i", "off", mount.path])
            try runProgram("/usr/sbin/diskutil", ["unmount", mount.path])
        }
        try runProgram("/sbin/fsck_msdos", ["-n", "/dev/r\(media.partition(2))"])
        try runProgram("/sbin/fsck_exfat", ["-n", "/dev/r\(media.partition(3))"])

        try? fm.removeItem(at: final)
        try fm.moveItem(at: partial, to: final)
        try Data("\(index)\n".utf8).write(to: indexFile)
        return (final, index)
    }

    private static func treeSize(_ root: URL, excluding skipped: URL) throws -> Int {
        var total = 0
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])!
        for case let file as URL in walker where file != skipped {
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values.isRegularFile == true { total += values.fileSize ?? 0 }
        }
        return total
    }

    /// The index of the Professional edition in a WIM, else the first image, read from the WIM's XML metadata.
    static func wimEditionIndex(_ wim: URL) throws -> Int {
        let handle = try FileHandle(forReadingFrom: wim)
        defer { try? handle.close() }
        guard let header = try handle.read(upToCount: 208), header.count == 208, header.prefix(5) == Data("MSWIM".utf8) else {
            throw CLIError.failure("\(wim.lastPathComponent) is not a WIM file")
        }
        // The XML resource's entry in the header: a 7-byte size, a flag byte, an 8-byte offset, an 8-byte original size.
        func integer(_ range: Range<Int>) -> Int { header[range].enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) } }
        let flags = header[79]
        let offset = integer(80..<88)
        let length = integer(88..<96)
        guard flags & 0x04 == 0, length > 0, length < (64 << 20) else { throw CLIError.failure("cannot read the WIM's image list") }
        try handle.seek(toOffset: UInt64(offset))
        guard let xml = try handle.read(upToCount: length), let text = String(data: xml, encoding: .utf16LittleEndian) else {
            throw CLIError.failure("cannot read the WIM's image list")
        }
        let images = try NSRegularExpression(pattern: #"<IMAGE INDEX="(\d+)">(.*?)</IMAGE>"#, options: [.dotMatchesLineSeparators])
        var first: Int?
        for match in images.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let indexRange = Range(match.range(at: 1), in: text), let bodyRange = Range(match.range(at: 2), in: text),
                  let index = Int(text[indexRange]) else { continue }
            first = first ?? index
            if text[bodyRange].contains("<EDITIONID>Professional</EDITIONID>") { return index }
        }
        guard let first else { throw CLIError.failure("the WIM lists no images") }
        note("terrarium: the installer has no Professional edition; installing its image \(first)")
        return first
    }
}
