import Foundation

/// Writes a file, leaving all-zero chunks as holes so raw disk images stay sparse.
final class SparseWriter {
    private let fd: Int32
    private var offset: off_t = 0
    private let zeros = [UInt8](repeating: 0, count: 1 << 20)

    init(_ url: URL) throws {
        fd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard fd >= 0 else { throw CLIError.failure("cannot create \(url.path): \(String(cString: strerror(errno)))") }
    }

    /// Writes a chunk of any size, leaving each all-zero megabyte of it as a hole.
    func write(_ chunk: Data) throws {
        var start = chunk.startIndex
        while start < chunk.endIndex {
            let end = min(start + zeros.count, chunk.endIndex)
            try writeSlice(chunk[start..<end])
            start = end
        }
    }

    /// Leaves a stretch of zeros as a hole.
    func skip(_ count: UInt64) {
        offset += off_t(count)
    }

    private func writeSlice(_ slice: Data) throws {
        let isHole = slice.withUnsafeBytes { memcmp($0.baseAddress!, zeros, slice.count) == 0 }
        if isHole {
            offset += off_t(slice.count)
            return
        }
        try slice.withUnsafeBytes { raw in
            var done = 0
            while done < raw.count {
                let n = pwrite(fd, raw.baseAddress! + done, raw.count - done, offset + off_t(done))
                guard n > 0 else { throw CLIError.failure("write failed: \(String(cString: strerror(errno)))") }
                done += n
            }
        }
        offset += off_t(slice.count)
    }

    func finish() throws {
        defer { close(fd) }
        guard ftruncate(fd, offset) == 0 else { throw CLIError.failure("truncate failed: \(String(cString: strerror(errno)))") }
    }
}
