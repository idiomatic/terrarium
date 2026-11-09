import Foundation

/// The image store: `<name>-<hash>.img` files in one directory.
enum Store {
    struct Image {
        /// `<name>-<hash>`, the IMAGE other verbs take.
        let name: String
        let url: URL
        let size: Int
        let onDisk: Int
        let created: Date

        /// The name without its `-<hash>` suffix.
        var baseName: String { Store.baseName(of: name) }
    }

    static func baseName(of name: String) -> String {
        name.range(of: "-[0-9a-f]{16}$", options: .regularExpression).map { String(name[..<$0.lowerBound]) } ?? name
    }

    /// How `images` and `ps` show an image: without its hash, unless another stored image has the same name without one
    /// (then the full `<name>-<hash>`, which `resolve` accepts).
    static func displayName(_ name: String, among images: [Image]) -> String {
        let base = baseName(of: name)
        return images.contains { $0.baseName == base && $0.name != name } ? name : base
    }

    static func ensure() throws {
        try FileManager.default.createDirectory(at: Paths.images, withIntermediateDirectories: true)
    }

    static func list() throws -> [Image] {
        try ensure()
        let keys: [URLResourceKey] = [.fileSizeKey, .fileAllocatedSizeKey, .creationDateKey]
        let files = try FileManager.default.contentsOfDirectory(at: Paths.images, includingPropertiesForKeys: keys)
        return try files.filter { $0.pathExtension == "img" }.map { url in
            let values = try url.resourceValues(forKeys: Set(keys))
            return Image(
                name: url.deletingPathExtension().lastPathComponent,
                url: url,
                size: values.fileSize ?? 0,
                onDisk: values.fileAllocatedSize ?? 0,
                created: values.creationDate ?? .distantPast)
        }.sorted { $0.name < $1.name }
    }

    /// What `--install` makes of an image, if it is an installer that nothing else can boot: the recipe's name.
    /// A macOS restore image is a zip file; a Windows ISO lists `install.wim` in its directory records, near the start (as
    /// ASCII, or as UTF-16 of either byte order). Other images, Alpine's ISO included, are not told from live ones.
    static func installer(_ image: Image) -> String? {
        if isRestoreImage(image) { return "macos" }
        guard let handle = try? FileHandle(forReadingFrom: image.url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 16 << 20) else { return nil }
        let found = ["install.wim", "INSTALL.WIM"].contains { name in
            [Data(name.utf8), Data(name.utf16.flatMap { [UInt8($0), 0] }), Data(name.utf16.flatMap { [0, UInt8($0)] })]
                .contains { head.range(of: $0) != nil }
        }
        return found ? "windows" : nil
    }

    /// A macOS restore image (an IPSW) is a zip file, stored as is.
    static func isRestoreImage(_ image: Image) -> Bool { (try? sniff(image.url)) == .zip }

    /// Finds a stored image by its full name, with or without `.img`, by its name without the hash when that is unique, or by a
    /// unique prefix.
    static func resolve(_ reference: String) throws -> Image {
        guard !reference.isEmpty, reference != ".img" else { throw CLIError.usage("an empty image name matches nothing") }
        let wanted = reference.hasSuffix(".img") ? String(reference.dropLast(4)) : reference
        let images = try list()
        if let exact = images.first(where: { $0.name == wanted }) { return exact }
        let named = images.filter { $0.baseName == wanted }
        if named.count == 1 { return named[0] }
        if named.count > 1 { throw CLIError.failure("'\(reference)' is ambiguous: " + named.map(\.name).joined(separator: ", ")) }
        let matches = images.filter { $0.name.hasPrefix(wanted) }
        switch matches.count {
        case 1: return matches[0]
        case 0: throw CLIError.failure("no stored image '\(reference)'")
        default: throw CLIError.failure("'\(reference)' is ambiguous: " + matches.map(\.name).joined(separator: ", "))
        }
    }

    /// Removes `*.partial.<pid>` and `*.partial.<pid>.<n>` files left by processes that no longer exist.
    static func sweepPartials() {
        for folder in [Paths.images, Paths.cache] {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for url in files {
                // `<name>.partial.<pid>`, or a build directory `build-<pid>` or `virtio-mount-<pid>`.
                let name = url.lastPathComponent
                let pid = name.components(separatedBy: ".partial.").last.flatMap { name.contains(".partial.") ? Int32($0.prefix { $0 != "." }) : nil }
                    ?? (["build-", "virtio-mount-"].first(where: name.hasPrefix).flatMap { Int32(name.dropFirst($0.count)) })
                if let pid, kill(pid, 0) != 0 && errno == ESRCH { try? FileManager.default.removeItem(at: url) }
            }
        }
    }

    static func table() throws -> String {
        let images = try list()
        guard !images.isEmpty else { return "" }
        // One SI prefix for the whole table, the largest that keeps its biggest value at 1 or more, after every value.
        let largest = images.map { max($0.size, $0.onDisk) }.max() ?? 0
        let (prefix, scale) = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3)].first { Double(largest) >= $0.1 } ?? ("B", 1)
        func amount(_ bytes: Int) -> String { String(format: "%.2f %@", Double(bytes) / scale, prefix) }
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd HH:mm"
        let rows = [["IMAGE", "KIND", "SIZE", "ON DISK", "CREATED"]] + images.map {
            [displayName($0.name, among: images), installer($0).map { "installer (\($0))" } ?? "live", amount($0.size), amount($0.onDisk), day.string(from: $0.created)]
        }
        let widths = (0..<5).map { c in rows.map { $0[c].count }.max()! }
        let rightAligned: Set<Int> = [2, 3]
        return rows.map { row in
            row.enumerated().map { column, text in
                let padding = String(repeating: " ", count: widths[column] - text.count)
                return rightAligned.contains(column) ? padding + text : text + padding
            }.joined(separator: "  ").trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n")
    }
}
