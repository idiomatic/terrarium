import CryptoKit
import Foundation

/// SHA-256 of the file followed by `suffix`, as lowercase hex.
func hashFile(_ url: URL, suffix: String) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while true {
        let more: Bool = try autoreleasepool {
            guard let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }
        if !more { break }
    }
    hasher.update(data: Data(suffix.utf8))
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}
