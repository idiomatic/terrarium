import Foundation

/// `pull`: download, decompress, convert, hash, and store an image.
enum Pull {
    /// Bump when the conversion recipe changes, so the same source hashes to a new image.
    static let recipeVersion = 1

    private static let calls = NSLock()
    private static var callCount = 0

    /// The scratch files' suffix: this process and this call, so concurrent pulls in one MCP server keep apart.
    private static func scratchSuffix() -> String {
        calls.lock()
        defer { calls.unlock() }
        callCount += 1
        return "\(getpid()).\(callCount)"
    }

    /// A URL's last path component as a file name in the store: decoded, it could hold `/` or start with `.`.
    static func safeFileName(_ url: URL) -> String {
        // A URL that ends in "/" has "/" as its last component: no file name at all.
        let component = url.lastPathComponent == "/" ? "" : url.lastPathComponent
        let name = component.replacingOccurrences(of: "/", with: "_")
        let trimmed = String(name.drop { $0 == "." })
        return trimmed.isEmpty ? "download" : trimmed
    }

    static func run(source: String) throws -> String {
        try Store.ensure()
        Store.sweepPartials()
        let pid = scratchSuffix()

        var downloaded: URL?
        defer { downloaded.map { try? FileManager.default.removeItem(at: $0) } }
        let input: URL
        let fileName: String
        if source.hasPrefix("http://") || source.hasPrefix("https://") {
            guard var url = URL(string: source) else { throw CLIError.usage("not a URL: \(source)") }
            // As with redirects: over HTTPS only, which App Transport Security requires anyway.
            if url.scheme == "http", var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                parts.scheme = "https"
                if let secure = parts.url { url = secure; note("fetching \(source) over HTTPS") }
            }
            fileName = safeFileName(url)
            let target = Paths.images.appendingPathComponent("\(fileName).partial.\(pid)")
            downloaded = target
            try download(url, to: target)
            input = target
        } else {
            input = URL(fileURLWithPath: (source as NSString).expandingTildeInPath)
            fileName = input.lastPathComponent
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: input.path, isDirectory: &isDirectory) else {
                throw CLIError.failure("no such file: \(input.path)")
            }
            if isDirectory.boolValue { throw CLIError.failure("\(input.path) is a directory; bundle images are not supported") }
        }

        note("hashing \(fileName)")
        let hash = String(try hashFile(input, suffix: "\nrecipe:\(recipeVersion)").prefix(16))
        let name = "\(baseName(fileName))-\(hash)"
        let final = Paths.images.appendingPathComponent("\(name).img")
        if FileManager.default.fileExists(atPath: final.path) {
            note("already stored")
            return name
        }

        let stage = Paths.images.appendingPathComponent("\(name).img.partial.\(pid)")
        var scratch = [stage]
        defer { scratch.forEach { try? FileManager.default.removeItem(at: $0) } }

        let packing = try sniff(input)
        switch packing {
        case .xz:
            note("decompressing (xz)")
            try decompressXZ(input, to: stage)
        case .gzip:
            note("decompressing (gzip)")
            try decompressGzip(input, to: stage)
        case .none:
            note("cloning")
            try cloneOrCopy(input, to: stage)
        case .zip:
            note("cloning (a macOS restore image, kept as is)")
            try cloneOrCopy(input, to: stage)
        }

        // What the archive and compression wrap: a tar archive of one disk image, which may be qcow2 in turn.
        var source = stage
        if isTar(stage) {
            note("extracting the disk image from the tar archive")
            let extracted = Paths.images.appendingPathComponent("\(name).img.extracted.partial.\(pid)")
            scratch.append(extracted)
            try extractSoleFile(from: stage, to: extracted)
            source = extracted
            try? FileManager.default.removeItem(at: stage)
        }
        var ready = source
        if isQcow2(source) {
            note("converting qcow2 to RAW")
            let converted = Paths.images.appendingPathComponent("\(name).img.converted.partial.\(pid)")
            scratch.append(converted)
            try Qcow2.convert(source, to: converted)
            ready = converted
        }
        let format = try packing == .zip || ready != source ? "RAW" : imageFormat(source)
        if format != "RAW" {
            note("converting \(format) to RAW")
            let converted = Paths.images.appendingPathComponent("\(name).img.converted.partial.\(pid)")
            scratch.append(converted)
            try runProgram("/usr/sbin/diskutil", ["image", "create", "from", "--format", "RAW", source.path, converted.path])
            ready = converted
        }

        if renamex_np(ready.path, final.path, UInt32(RENAME_EXCL)) != 0 {
            // Another pull stored the same image first: it is the same bytes, and already set up.
            guard errno == EEXIST else { throw CLIError.failure("cannot store image: \(String(cString: strerror(errno)))") }
            return name
        }
        // A clone keeps its source's dates; `images` shows when the image was stored.
        // Stored images are base images: read-only.
        try FileManager.default.setAttributes([.creationDate: Date(), .posixPermissions: 0o444], ofItemAtPath: final.path)
        return name
    }

    /// The file name without compression and disk-image extensions.
    static func baseName(_ fileName: String) -> String {
        var name = fileName
        for ext in [".xz", ".gz", ".tgz"] where name.hasSuffix(ext) { name = String(name.dropLast(ext.count)) }
        for ext in [".tar", ".img", ".raw", ".qcow2", ".iso", ".asif", ".dmg", ".ipsw"] where name.hasSuffix(ext) { name = String(name.dropLast(ext.count)) }
        return name
    }

    /// `diskutil image info` format of the file: RAW for raw disks and ISOs.
    static func imageFormat(_ url: URL) throws -> String {
        let data = try runProgram("/usr/sbin/diskutil", ["image", "info", "--plist", url.path])
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let format = plist["Image Format"] as? String else {
            throw CLIError.failure("cannot identify the image format of \(url.lastPathComponent)")
        }
        return format
    }

    /// `clonefile(2)` on the same APFS volume, else a plain copy.
    static func cloneOrCopy(_ source: URL, to destination: URL) throws {
        if clonefile(source.path, destination.path, 0) == 0 { return }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    static func download(_ url: URL, to destination: URL) throws {
        note("downloading \(url.absoluteString)")
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var failure: Error?
        let session = URLSession(configuration: .default, delegate: HTTPSRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: url) { temporary, response, error in
            defer { done.signal() }
            if let error { failure = error; return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let temporary else {
                failure = CLIError.failure("download failed: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return
            }
            do { try FileManager.default.moveItem(at: temporary, to: destination) } catch { failure = error }
        }
        let tty = isatty(STDERR_FILENO) != 0
        nonisolated(unsafe) var last = -1
        let progress = task.progress.observe(\.fractionCompleted) { p, _ in
            let percent = Int(p.fractionCompleted * 100)
            if tty && percent != last { last = percent; FileHandle.standardError.write(Data("\r  \(percent)%".utf8)) }
        }
        task.resume()
        done.wait()
        progress.invalidate()
        if tty { FileHandle.standardError.write(Data("\r".utf8)) }
        if let failure { throw failure }
    }
}

/// Follows redirects over HTTPS only: a server that redirects to `http://` (fedorapeople.org does) is asked again over
/// `https://`, which App Transport Security would otherwise refuse. A redirect is never downgraded.
private final class HTTPSRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == "http", var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return completionHandler(request)
        }
        parts.scheme = "https"
        var upgraded = request
        upgraded.url = parts.url
        completionHandler(upgraded)
    }
}
