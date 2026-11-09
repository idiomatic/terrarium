import Foundation

/// Whether the file is a tar archive (`ustar` at offset 257, as POSIX and GNU tar write it).
func isTar(_ url: URL) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? handle.close() }
    guard (try? handle.seek(toOffset: 257)) != nil else { return false }
    return [UInt8]((try? handle.read(upToCount: 5)) ?? Data()) == Array("ustar".utf8)
}

/// Writes the one file in a tar archive to `destination`, leaving zero blocks as holes. An archive of several files
/// is refused: `pull` stores one disk image, and cannot tell which member is it.
func extractSoleFile(from archive: URL, to destination: URL) throws {
    let listing = String(decoding: try runProgram("/usr/bin/tar", ["-tf", archive.path]), as: UTF8.self)
    let members = listing.split(separator: "\n").map(String.init).filter {
        !$0.hasSuffix("/") && !($0 as NSString).lastPathComponent.hasPrefix("._")
    }
    guard members.count == 1, let member = members.first else {
        throw CLIError.failure("\(archive.lastPathComponent) holds \(members.count) files; pull needs a tar archive of one disk image")
    }

    try streamSparse("/usr/bin/tar", ["-xOf", archive.path, member], to: destination)
}

/// Runs a stock program and writes its standard output to `destination`, leaving zero blocks as holes.
func streamSparse(_ path: String, _ arguments: [String], to destination: URL) throws {
    let name = URL(fileURLWithPath: path).lastPathComponent
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err
    try process.run()
    defer {
        try? out.fileHandleForReading.close()
        try? err.fileHandleForReading.close()
    }
    // Its messages are read alongside, so a full stderr pipe cannot stall it.
    nonisolated(unsafe) var errorData = Data()
    let reader = DispatchGroup()
    DispatchQueue.global().async(group: reader) { errorData = err.fileHandleForReading.readDataToEndOfFile() }
    do {
        let writer = try SparseWriter(destination)
        while let chunk = try out.fileHandleForReading.read(upToCount: 1 << 20), !chunk.isEmpty {
            try writer.write(chunk)
        }
        try writer.finish()
    } catch {
        process.terminate()
        process.waitUntilExit()
        reader.wait()
        throw error
    }
    process.waitUntilExit()
    reader.wait()
    guard process.terminationStatus == 0 else {
        let text = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        throw CLIError.failure("\(name) failed (exit \(process.terminationStatus))" + (text.isEmpty ? "" : ": \(text)"))
    }
}
