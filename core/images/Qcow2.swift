import Compression
import Foundation

/// Converts a qcow2 image (version 2 or 3) to a raw disk, so `pull` can store images that only ship as qcow2.
/// It reads what cloud images use: plain and zlib-compressed clusters, zero clusters, and unallocated ones.
/// Backing files, encryption, extended L2 entries, and zstd compression are refused, and so is a header whose tables lie
/// outside the file or that describes more than terrarium handles.
enum Qcow2 {
    /// Writes the guest-visible disk of `source` to `destination`, leaving zero clusters as holes.
    static func convert(_ source: URL, to destination: URL) throws {
        let fd = open(source.path, O_RDONLY)
        guard fd >= 0 else { throw CLIError.failure("cannot open \(source.lastPathComponent): \(String(cString: strerror(errno)))") }
        defer { close(fd) }
        var status = stat()
        guard fstat(fd, &status) == 0 else { throw CLIError.failure("cannot read \(source.lastPathComponent)") }
        let fileSize = UInt64(status.st_size)
        let damaged = CLIError.failure("\(source.lastPathComponent) is truncated or damaged")

        /// Reads `count` bytes at `offset`; with `upTo`, fewer when the file ends first.
        func read(_ count: Int, at offset: UInt64, upTo: Bool = false) throws -> [UInt8] {
            guard offset <= fileSize, let start = off_t(exactly: offset) else { throw damaged }
            var buffer = [UInt8](repeating: 0, count: count)
            var done = 0
            while done < count {
                let n = buffer.withUnsafeMutableBytes { pread(fd, $0.baseAddress! + done, count - done, start + off_t(done)) }
                if n == 0 && upTo { return Array(buffer[0..<done]) }
                guard n > 0 else { throw damaged }
                done += n
            }
            return buffer
        }
        func be32(_ b: [UInt8], _ at: Int) -> UInt32 { b[at..<at + 4].reduce(0) { $0 << 8 | UInt32($1) } }
        func be64(_ b: [UInt8], _ at: Int) -> UInt64 { b[at..<at + 8].reduce(0) { $0 << 8 | UInt64($1) } }

        let header = try read(112, at: 0)
        let version = be32(header, 4)
        guard be32(header, 0) == 0x514649FB, version == 2 || version == 3 else {
            throw CLIError.failure("\(source.lastPathComponent) is not a qcow2 version 2 or 3 image")
        }
        guard be64(header, 8) == 0 else { throw CLIError.failure("the qcow2 image has a backing file, which terrarium does not follow") }
        guard be32(header, 32) == 0 else { throw CLIError.failure("the qcow2 image is encrypted") }
        if version == 3 {
            guard be64(header, 72) == 0 else {
                throw CLIError.failure("the qcow2 image uses features terrarium cannot read (incompatible features \(String(be64(header, 72), radix: 16)))")
            }
            // The compression type exists only in headers longer than 104 bytes; in a shorter one, byte 104 starts an extension.
            guard be32(header, 100) <= 104 || header[104] == 0 else {
                throw CLIError.failure("the qcow2 image is zstd-compressed, which terrarium cannot read")
            }
        }
        let clusterBits = Int(be32(header, 20))
        guard (9...21).contains(clusterBits) else { throw CLIError.failure("the qcow2 image has an invalid cluster size") }
        let clusterSize = 1 << clusterBits
        let size = be64(header, 24)
        guard size <= 1 << 46 else { throw CLIError.failure("the qcow2 image's disk is larger than 64 TiB, which terrarium does not handle") }
        let l2Entries = clusterSize / 8
        let bytesPerL1 = UInt64(clusterSize) * UInt64(l2Entries)
        // Only the L1 entries the disk's size needs are read; they must lie within the file.
        let l1Count = min(Int(be32(header, 36)), Int((size + bytesPerL1 - 1) / bytesPerL1))
        let l1Offset = be64(header, 40)
        guard l1Offset <= fileSize, UInt64(l1Count) * 8 <= fileSize - l1Offset else { throw damaged }
        let l1Raw = try read(l1Count * 8, at: l1Offset)
        let l1 = (0..<l1Count).map { be64(l1Raw, $0 * 8) & 0x00FF_FFFF_FFFF_FE00 }

        let writer = try SparseWriter(destination)
        let zeros = Data(count: clusterSize)
        let compressedShift = UInt64(62 - (clusterBits - 8))
        let sectorMask = (UInt64(1) << UInt64(clusterBits - 8)) - 1
        var cachedIndex = -1
        var l2: [UInt8] = []
        var guest: UInt64 = 0
        var cluster = 0
        var scratch = [UInt8](repeating: 0, count: clusterSize)
        while guest < size {
            let index = cluster / l2Entries
            if index != cachedIndex {
                cachedIndex = index
                l2 = index < l1Count && l1[index] != 0 ? try read(clusterSize, at: l1[index]) : []
            }
            if l2.isEmpty {
                // A whole L2 table's range is unallocated: a hole.
                let skip = min(UInt64(l2Entries - cluster % l2Entries) * UInt64(clusterSize), size - guest)
                writer.skip(skip)
                guest += skip
                cluster += Int((skip + UInt64(clusterSize) - 1) / UInt64(clusterSize))
                continue
            }
            let entry = be64(l2, (cluster % l2Entries) * 8)
            var data = zeros
            if entry & (1 << 62) != 0 {
                let offset = entry & ((UInt64(1) << compressedShift) - 1)
                let length = Int(((entry >> compressedShift) & sectorMask) + 1) * 512 - Int(offset & 511)
                // The last compressed cluster need not fill its final sector, so the file may end inside it.
                let packed = try read(length, at: offset, upTo: true)
                let produced = scratch.withUnsafeMutableBytes { out in
                    packed.withUnsafeBytes { compression_decode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, clusterSize, $0.bindMemory(to: UInt8.self).baseAddress!, packed.count, nil, COMPRESSION_ZLIB) }
                }
                guard produced == clusterSize else { throw CLIError.failure("a compressed cluster of the qcow2 image is damaged") }
                data = Data(scratch)
            } else if entry & 1 == 0 && entry & 0x00FF_FFFF_FFFF_FE00 != 0 {
                data = Data(try read(clusterSize, at: entry & 0x00FF_FFFF_FFFF_FE00))
            }
            try writer.write(data.prefix(Int(min(UInt64(clusterSize), size - guest))))
            guest += UInt64(clusterSize)
            cluster += 1
        }
        try writer.finish()
    }
}

/// Whether the file is a qcow2 image (magic `QFI\xFB`), which neither `diskutil` nor Virtualization reads: it would be stored
/// as if it were a raw disk and could not boot.
func isQcow2(_ url: URL) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? handle.close() }
    return [UInt8]((try? handle.read(upToCount: 4)) ?? Data()) == [0x51, 0x46, 0x49, 0xFB]
}
