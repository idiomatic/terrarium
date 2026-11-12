import Foundation

/// `squash LAYER NEWLAYER [--onto ANCESTOR]`: saves NEWLAYER, one layer holding LAYER's changes and those of its ancestors
/// above ANCESTOR, with no VM. It attaches two stacks with `diskutil`: A, LAYER's whole chain and delta, read-only; and B,
/// ANCESTOR's chain under a new shadow, which `diskutil` makes as an ASIF child of ANCESTOR's top file. It writes into B each
/// block where A differs (unmapping one where A reads zeros, which masks what is below), checks that A and B read alike,
/// and saves B's shadow as NEWLAYER's delta. LAYER is left as it is.
enum Squash {
    /// The unit compared, written, and unmapped.
    static let block = 4096
    /// What is read at once from each stack.
    static let stride = 8 << 20

    static func run(_ inv: Invocation) throws -> String {
        let bundle = try LayerStore.resolve(inv.values["layer"]!)
        let manifest = try LayerManifest.read(bundle)
        let files = try LayerStore.chainFiles(of: bundle, manifest)
        let kept = try keptCount(inv.values["onto"], chain: manifest.chain, files: files)
        let target = LayerStore.location(inv.values["newlayer"]!)
        try Owner.checkSaveTarget(target, startedFrom: nil)
        let lock = try LayerLock.acquire(target)
        defer { LayerLock.release(lock, target) }
        guard !FileManager.default.fileExists(atPath: target.path) else { throw CLIError.failure("\(target.path) already exists") }

        let manager = FileManager.default
        let partial = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).partial.\(getpid())", isDirectory: true)
        try? manager.removeItem(at: partial)
        let chainDirectory = partial.appendingPathComponent(LayerManifest.chainDirectory, isDirectory: true)
        let scratch = partial.appendingPathComponent("scratch", isDirectory: true)
        var attached: [Attached.Handle] = []
        do {
            try manager.createDirectory(at: chainDirectory, withIntermediateDirectories: true)
            try manager.createDirectory(at: scratch, withIntermediateDirectories: true)
            // The base is the image at the chain's root, or the blank disk under a root layer.
            let rootIsImage = files.first?.isImage == true
            let base = rootIsImage ? files[0].url : try Recipe.blankDisk(gigabytes: manifest.diskGB, in: scratch)
            let above = Array(files.dropFirst(rootIsImage ? 1 : 0))
            let layerDelta = bundle.appendingPathComponent(LayerManifest.deltaFile)
            let delta = partial.appendingPathComponent(LayerManifest.deltaFile)
            // NEWLAYER's chain is cloned first, and B reads it, so the shadow's parent is a file of the bundle it goes in.
            var chain: [URL] = []
            for (index, file) in files.prefix(kept).enumerated() {
                let copy = chainDirectory.appendingPathComponent(file.name(at: index))
                try Pull.cloneOrCopy(file.url, to: copy)
                chain.append(copy)
            }
            let keptAbove = Array(chain.dropFirst(rootIsImage ? 1 : 0))
            note("squashing \(bundle.deletingPathExtension().lastPathComponent): \(files.count + 1) files into \(kept + 1)")
            let a = try Attached.attach(base, shadows: above.map(\.url) + [layerDelta], readOnly: true)
            attached.append(a)
            let b = try Attached.attach(rootIsImage ? chain[0] : base, shadows: keptAbove + [delta])
            attached.append(b)
            try copyDifferences(from: "/dev/r" + a.device, to: "/dev/r" + b.device)
            for handle in attached.reversed() { Attached.eject(handle) }
            attached = []
            try? manager.removeItem(at: scratch)

            // A macOS guest's identity files and auxiliary storage go with its disk.
            for name in try manager.contentsOfDirectory(atPath: bundle.path)
            where ![LayerManifest.fileName, LayerManifest.chainDirectory, LayerManifest.deltaFile].contains(name) && !name.hasPrefix(".") {
                try Pull.cloneOrCopy(bundle.appendingPathComponent(name), to: partial.appendingPathComponent(name))
            }
            let squashed = LayerManifest(guest: manifest.guest, diskGB: manifest.diskGB, installer: manifest.installer, id: LayerManifest.newID(), chain: Array(manifest.chain.prefix(kept)))
            try squashed.write(to: partial)
            guard renamex_np(partial.path, target.path, UInt32(RENAME_EXCL)) == 0 else {
                throw CLIError.failure(errno == EEXIST ? "\(target.path) already exists" : "cannot save \(target.path): \(String(cString: strerror(errno)))")
            }
            let bytes = (try? target.appendingPathComponent(LayerManifest.deltaFile).resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize) ?? 0
            return "\(target.path) (\(manifest.chain.count + 1) deep, now \(kept + 1); delta \(String(format: "%.2f", Double(bytes) / 1e9)) GB)"
        } catch {
            for handle in attached.reversed() { Attached.eject(handle) }
            try? manager.removeItem(at: partial)
            throw error
        }
    }

    /// How many of the chain's files NEWLAYER keeps: those up to and including ANCESTOR. ANCESTOR is an id or image name in
    /// the chain, a stored image, or a layer whose id is in the chain; without it, the image at the root, or nothing over a
    /// blank disk.
    static func keptCount(_ onto: String?, chain: [String], files: [ChainFile]) throws -> Int {
        guard let onto else { return files.first?.isImage == true ? 1 : 0 }
        var ids = [onto]
        if let image = try? Store.resolve(onto) { ids.append(image.name) }
        if case .layer(let url)? = try? LayerStore.target(onto), let manifest = try? LayerManifest.read(url) { ids.append(manifest.id) }
        guard let index = chain.lastIndex(where: { ids.contains($0) }) else {
            throw CLIError.usage("--onto \(onto) is not in the layer's chain: name an ancestor, a layer or image it was made from")
        }
        return index + 1
    }

    /// Writes into `destination` each block where `source` differs, unmapping one where `source` reads zeros, then reads both
    /// again and fails if they differ anywhere.
    static func copyDifferences(from source: String, to destination: String) throws {
        let a = open(source, O_RDONLY), b = open(destination, O_RDWR)
        defer {
            if a >= 0 { close(a) }
            if b >= 0 { close(b) }
        }
        guard a >= 0, b >= 0 else { throw CLIError.failure("cannot open the attached disks: \(String(cString: strerror(errno)))") }
        let size = try deviceSize(a)
        guard try deviceSize(b) == size else { throw CLIError.failure("the squashed disk is not the size of the layer's") }
        // Raw devices take block-aligned buffers.
        let x = UnsafeMutableRawPointer.allocate(byteCount: stride, alignment: 16384), y = UnsafeMutableRawPointer.allocate(byteCount: stride, alignment: 16384)
        let zero = UnsafeMutableRawPointer.allocate(byteCount: block, alignment: 16384)
        defer { x.deallocate(); y.deallocate(); zero.deallocate() }
        memset(zero, 0, block)
        var unmapWorks = true
        var shown = -1
        for offset in Swift.stride(from: 0, to: size, by: stride) {
            let count = min(stride, size - offset)
            try readFully(a, x, count, offset)
            try readFully(b, y, count, offset)
            let percent = offset * 100 / size
            if percent / 10 != shown / 10 { note("  \(percent)%"); shown = percent }
            if memcmp(x, y, count) == 0 { continue }
            var start = 0
            while start < count {
                guard memcmp(x + start, y + start, block) != 0 else { start += block; continue }
                // A run of differing blocks, all zero in the source or all not.
                let zeros = memcmp(x + start, zero, block) == 0
                var end = start + block
                while end < count, memcmp(x + end, y + end, block) != 0, (memcmp(x + end, zero, block) == 0) == zeros { end += block }
                // A disk that refuses an unmap gets written zeros from then on, which read the same but take space.
                let unmapped = zeros && unmapWorks && unmap(b, offset: offset + start, length: end - start)
                if zeros && !unmapped { unmapWorks = false }
                if !unmapped, pwrite(b, x + start, end - start, off_t(offset + start)) != end - start {
                    throw CLIError.failure("cannot write the squashed disk: \(String(cString: strerror(errno)))")
                }
                start = end
            }
        }
        guard fsync(b) == 0 else { throw CLIError.failure("cannot flush the squashed disk: \(String(cString: strerror(errno)))") }
        note("  checking")
        for offset in Swift.stride(from: 0, to: size, by: stride) {
            let count = min(stride, size - offset)
            try readFully(a, x, count, offset)
            try readFully(b, y, count, offset)
            guard memcmp(x, y, count) == 0 else { throw CLIError.failure("the squashed disk differs from the layer's at byte \(offset)") }
        }
    }

    private static func readFully(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int, _ offset: Int) throws {
        guard pread(fd, buffer, count, off_t(offset)) == count else {
            throw CLIError.failure("cannot read an attached disk at byte \(offset): \(String(cString: strerror(errno)))")
        }
    }

    /// `DKIOCGETBLOCKSIZE` and `DKIOCGETBLOCKCOUNT`, from `<sys/disk.h>`, which Swift does not import.
    private static func deviceSize(_ fd: Int32) throws -> Int {
        var blockSize: UInt32 = 0
        var blocks: UInt64 = 0
        guard ioctl(fd, 0x4004_6418, &blockSize) == 0, ioctl(fd, 0x4008_6419, &blocks) == 0 else {
            throw CLIError.failure("cannot read an attached disk's size: \(String(cString: strerror(errno)))")
        }
        return Int(blockSize) * Int(blocks)
    }

    /// `DKIOCUNMAP` for one extent: a `dk_unmap_t` (pointer to `dk_extent_t`s, their count, options), laid out by hand.
    private static func unmap(_ fd: Int32, offset: Int, length: Int) -> Bool {
        var extent: (UInt64, UInt64) = (UInt64(offset), UInt64(length))
        return withUnsafeMutablePointer(to: &extent) { pointer in
            var request: (UnsafeMutableRawPointer, UInt32, UInt32) = (UnsafeMutableRawPointer(pointer), 1, 0)
            return ioctl(fd, 0x8010_641F, &request) == 0
        }
    }
}
