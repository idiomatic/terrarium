import Foundation

/// `layers` and `rm`: the layer store.
enum LayerVerbs {
    private struct Entry {
        let url: URL
        let name: String
        let manifest: LayerManifest
        let delta: Int
        let chain: Int
    }

    /// The bytes a file takes on disk (a clone's bytes are shared with the file it came from).
    private static func allocated(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize) ?? 0
    }

    private static func entry(_ url: URL) -> Entry? {
        guard let manifest = try? LayerManifest.read(url) else { return nil }
        let manager = FileManager.default
        let identity = ((try? manager.contentsOfDirectory(atPath: url.path)) ?? []).filter { $0 != LayerManifest.fileName && $0 != LayerManifest.chainDirectory }
        let chain = ((try? manager.contentsOfDirectory(atPath: url.appendingPathComponent(LayerManifest.chainDirectory).path)) ?? [])
        return Entry(
            url: url, name: url.deletingPathExtension().lastPathComponent, manifest: manifest,
            delta: identity.reduce(0) { $0 + allocated(url.appendingPathComponent($1)) },
            chain: chain.reduce(0) { $0 + allocated(url.appendingPathComponent(LayerManifest.chainDirectory).appendingPathComponent($1)) })
    }

    /// The store as a tree: images that have layers as roots, a layer under its parent, two spaces to a level. A layer whose
    /// parent is gone (removed, or saved elsewhere) is a root marked `(gone: ID)`. Roots are listed by name, children by
    /// creation time.
    static func table() throws -> String {
        let entries = LayerStore.list().compactMap(entry)
        guard !entries.isEmpty else { return "" }
        let images = (try? Store.list()) ?? []
        func created(_ entry: Entry) -> Date {
            (try? entry.url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        }
        let byID = Dictionary(entries.map { ($0.manifest.id, $0) }, uniquingKeysWith: { first, _ in first })
        var children: [String: [Entry]] = [:]
        var roots: [(label: String, entry: Entry)] = []
        for entry in entries {
            guard let parent = entry.manifest.chain.last else { roots.append((entry.name, entry)); continue }
            if byID[parent] != nil || images.contains(where: { $0.name == parent }) {
                children[parent, default: []].append(entry)
            } else {
                roots.append((entry.name + "  (gone: \(parent))", entry))
            }
        }
        var rows: [[String]] = [["NAME", "OS", "DELTA", "CHAIN"]]
        let largest = entries.map { max($0.delta, $0.chain) }.max() ?? 0
        let (prefix, scale) = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3)].first { Double(largest) >= $0.1 } ?? ("B", 1)
        func amount(_ bytes: Int) -> String { bytes == 0 ? "-" : String(format: "%.2f %@", Double(bytes) / scale, prefix) }
        func add(_ entry: Entry, label: String, depth: Int) {
            rows.append([String(repeating: "  ", count: depth) + label, entry.manifest.guest, amount(entry.delta), amount(entry.chain)])
            for child in (children[entry.manifest.id] ?? []).sorted(by: { created($0) < created($1) }) { add(child, label: child.name, depth: depth + 1) }
        }
        for image in images where children[image.name] != nil {
            rows.append([Store.displayName(image.name, among: images), "(image)", "", ""])
            for child in (children[image.name] ?? []).sorted(by: { created($0) < created($1) }) { add(child, label: child.name, depth: 1) }
        }
        for root in roots.sorted(by: { $0.entry.name < $1.entry.name }) { add(root.entry, label: root.label, depth: 0) }
        let widths = (0..<4).map { column in rows.map { $0[column].count }.max()! }
        return rows.map { row in
            row.enumerated().map { column, text in
                let padding = String(repeating: " ", count: widths[column] - text.count)
                return column >= 2 ? padding + text : text + padding
            }.joined(separator: "  ").replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        }.joined(separator: "\n")
    }

    /// Removes a layer. Layers made from it stay whole; a running VM that started from it keeps it.
    static func remove(_ reference: String) throws -> String {
        let bundle = try LayerStore.resolve(reference)
        guard (try? LayerManifest.read(bundle)) != nil else { throw CLIError.failure("\(bundle.path) is not a layer: no \(LayerManifest.fileName)") }
        if let running = Runtime.list().first(where: { $0.image == BootRequest.display(bundle) }) {
            throw CLIError.failure("VM \(running.id) started from \(bundle.lastPathComponent): stop it first")
        }
        try FileManager.default.removeItem(at: bundle)
        return bundle.deletingPathExtension().lastPathComponent
    }
}
