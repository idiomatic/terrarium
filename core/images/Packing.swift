import Compression
import Foundation

enum Packing {
    case none
    case xz
    case gzip
    case zip
}

/// Identifies compression by magic bytes, not by file name.
func sniff(_ url: URL) throws -> Packing {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let head = [UInt8](try handle.read(upToCount: 6) ?? Data())
    if head == [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00] { return .xz }
    if head.starts(with: [0x1F, 0x8B]) { return .gzip }
    if head.starts(with: [0x50, 0x4B, 0x03, 0x04]) { return .zip }
    return .none
}

/// Decompresses an `.xz` stream with the Compression framework's LZMA decoder.
func decompressXZ(_ source: URL, to destination: URL) throws {
    let input = try FileHandle(forReadingFrom: source)
    defer { try? input.close() }
    let filter = try InputFilter(.decompress, using: .lzma) { (length: Int) -> Data? in
        let data = try input.read(upToCount: length)
        return (data?.isEmpty ?? true) ? nil : data
    }
    let writer = try SparseWriter(destination)
    while let chunk = try filter.readData(ofLength: 1 << 20) {
        try writer.write(chunk)
    }
    try writer.finish()
}

/// Decompresses a gzip stream with the stock `gunzip`.
func decompressGzip(_ source: URL, to destination: URL) throws {
    try streamSparse("/usr/bin/gunzip", ["-c", source.path], to: destination)
}
