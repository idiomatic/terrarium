import Foundation

/// `layers` and `rm`: the layer store.
enum LayerVerbs {
    private struct Entry {
        let url: URL
        let name: String
        let manifest: LayerManifest
        let delta: Int
        let chain: Int
        /// What a pending layer or one about to be replaced says of itself: `(saved when VM ID stops)`.
        var note = ""
        var created: Date?
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
        var entries = LayerStore.list().compactMap(entry)
        // A layer a running VM will save is listed too, under the parent it will have; a layer it will replace says so.
        let pending = Runtime.list().compactMap { info in info.saveTo.map { (info, URL(fileURLWithPath: $0)) } }
        var elsewhere: [String] = []
        for (info, target) in pending {
            let note = "(saved when VM \(info.id) stops)"
            if let index = entries.firstIndex(where: { $0.url.standardizedFileURL == target.standardizedFileURL }) {
                entries[index].note = "(replaced when VM \(info.id) stops)"
            } else if target.deletingLastPathComponent().standardizedFileURL == Paths.layers.standardizedFileURL {
                let manifest = LayerManifest(guest: info.guest ?? "-", diskGB: 0, installer: "", id: "pending-\(info.id)", chain: info.saveParent.map { [$0] } ?? [])
                let delta = allocated(Runtime.dir(info.id).appendingPathComponent(MacFiles.layer))
                entries.append(Entry(url: target, name: target.deletingPathExtension().lastPathComponent, manifest: manifest, delta: delta, chain: 0, note: note, created: info.started))
            } else {
                elsewhere.append("also pending: \(target.path) \(note)")
            }
        }
        guard !entries.isEmpty || !elsewhere.isEmpty else { return "" }
        let images = (try? Store.list()) ?? []
        func created(_ entry: Entry) -> Date {
            entry.created ?? (try? entry.url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
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
        var rows: [[String]] = [["NAME", "OS", "DELTA", "CHAIN", ""]]
        let largest = entries.map { max($0.delta, $0.chain) }.max() ?? 0
        let (prefix, scale) = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3)].first { Double(largest) >= $0.1 } ?? ("B", 1)
        func amount(_ bytes: Int) -> String { bytes == 0 ? "-" : String(format: "%.2f %@", Double(bytes) / scale, prefix) }
        func add(_ entry: Entry, label: String, depth: Int) {
            rows.append([String(repeating: "  ", count: depth) + label, entry.manifest.guest, amount(entry.delta), amount(entry.chain), entry.note])
            for child in (children[entry.manifest.id] ?? []).sorted(by: { created($0) < created($1) }) { add(child, label: child.name, depth: depth + 1) }
        }
        for image in images where children[image.name] != nil {
            rows.append([Store.displayName(image.name, among: images), "(image)", "", "", ""])
            for child in (children[image.name] ?? []).sorted(by: { created($0) < created($1) }) { add(child, label: child.name, depth: 1) }
        }
        for root in roots.sorted(by: { $0.entry.name < $1.entry.name }) { add(root.entry, label: root.label, depth: 0) }
        let widths = (0..<5).map { column in rows.map { $0[column].count }.max()! }
        let table = rows.map { row in
            row.enumerated().map { column, text in
                let padding = String(repeating: " ", count: widths[column] - text.count)
                return column == 2 || column == 3 ? padding + text : text + padding
            }.joined(separator: "  ").replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        }
        return (rows.count > 1 ? table : []).joined(separator: "\n") + (elsewhere.isEmpty ? "" : (rows.count > 1 ? "\n\n" : "") + elsewhere.joined(separator: "\n"))
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
