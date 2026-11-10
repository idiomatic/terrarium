import Foundation

/// A saved layer is a bundle `NAME.layer/`: this manifest, `chain/` (clones of the ancestors' files, root first, as
/// `<n>-<id>.asif`, or `<n>-<name>.img` for an image), `delta.asif` (its own changes from its parent), and for macOS the
/// identity files and auxiliary storage. A layer whose chain does not begin with an image has a blank disk of `diskGB`
/// as its root, which terrarium regenerates.
struct LayerManifest: Codable {
    static let fileName = "manifest.json"
    static let suffix = ".layer"
    static let deltaFile = "delta.asif"
    static let chainDirectory = "chain"
    static let currentVersion = 2

    var version = LayerManifest.currentVersion
    /// `windows`, `macos`, or `linux`.
    var guest: String
    var diskGB: Int
    /// The installer image it was installed from, kept as provenance.
    var installer: String
    /// 16 hex digits, chosen at every `commit`.
    var id: String
    /// The ancestors' ids, root first; an image by its name (with its hash).
    var chain: [String]

    static func newID() -> String { String(format: "%016llx", UInt64.random(in: .min ... .max)) }

    /// The manifest of the layer at `bundle`. A directory without one is not a layer; one saved by an earlier terrarium
    /// (version 1, an installed guest) is refused.
    static func read(_ bundle: URL) throws -> LayerManifest {
        guard let data = try? Data(contentsOf: bundle.appendingPathComponent(fileName)) else {
            throw CLIError.failure("\(bundle.path) is not a layer: no \(fileName)")
        }
        struct Version: Codable { var version: Int }
        guard let found = try? JSONDecoder().decode(Version.self, from: data), found.version == currentVersion,
              let manifest = try? JSONDecoder().decode(LayerManifest.self, from: data) else {
            throw CLIError.failure("\(bundle.lastPathComponent) was saved by an earlier terrarium: install it again")
        }
        return manifest
    }

    func write(to bundle: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: bundle.appendingPathComponent(Self.fileName))
    }

    var kind: GuestKind {
        switch guest {
        case "macos": return .macos
        case "linux": return .linux
        default: return .windows
        }
    }

    static func name(of kind: GuestKind) -> String {
        switch kind {
        case .macos: return "macos"
        case .windows: return "windows"
        case .linux: return "linux"
        }
    }
}

/// One file of a layer's chain: read-only under the VM's own delta.
struct ChainFile {
    /// A layer's `id`, or an image's name.
    let id: String
    var url: URL
    /// A stored image (a raw disk, the root of its chain), not a layer's delta.
    let isImage: Bool

    /// The file's name in `chain/` at position `index`.
    func name(at index: Int) -> String { "\(index)-\(id).\(isImage ? "img" : "asif")" }
}

/// The layer store and the arguments that name layers.
enum LayerStore {
    /// An argument with a `/`, or ending `.layer`, or starting `~` is a path; anything else names a layer in the store.
    static func isPath(_ reference: String) -> Bool {
        reference.contains("/") || reference.hasPrefix("~") || reference.hasSuffix(LayerManifest.suffix)
    }

    /// Where a layer of this name or path is (or would be saved): the store's `NAME.layer` for a name, else the path with
    /// `.layer` added when it has none.
    static func location(_ reference: String) -> URL {
        if !isPath(reference) { return Paths.layers.appendingPathComponent(reference + LayerManifest.suffix, isDirectory: true) }
        let expanded = (reference as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded.hasSuffix(LayerManifest.suffix) ? expanded : expanded + LayerManifest.suffix).standardizedFileURL
    }

    /// The bundle of a layer that exists.
    static func resolve(_ reference: String) throws -> URL {
        let url = location(reference)
        guard FileManager.default.fileExists(atPath: url.path) else { throw CLIError.failure("no layer '\(reference)': \(url.path)") }
        return url
    }

    /// The layers in the store, by name.
    static func list() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: Paths.layers, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "layer" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// What a bare argument of `start` or `run` names: an image, or a layer in the store. One name for both is refused.
    enum Target {
        case image(Store.Image)
        case layer(URL)
    }

    static func target(_ reference: String) throws -> Target {
        if isPath(reference) { return .layer(try resolve(reference)) }
        let layer = location(reference)
        let isLayer = FileManager.default.fileExists(atPath: layer.path)
        let image = try? Store.resolve(reference)
        switch (image, isLayer) {
        case (let image?, true):
            throw CLIError.failure("'\(reference)' names both the image \(image.name) and the layer \(layer.lastPathComponent): say layers/ or a path for the layer, or the image's full name")
        case (let image?, false): return .image(image)
        case (nil, true): return .layer(layer)
        case (nil, false): throw CLIError.failure("no stored image or layer '\(reference)'")
        }
    }

    /// The chain files of the bundle, root first, checked against the manifest: a file missing or misnamed is a damaged layer.
    static func chainFiles(of bundle: URL, _ manifest: LayerManifest) throws -> [ChainFile] {
        let directory = bundle.appendingPathComponent(LayerManifest.chainDirectory, isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var files: [ChainFile] = []
        for (index, id) in manifest.chain.enumerated() {
            let isImage = names.contains("\(index)-\(id).img")
            let file = ChainFile(id: id, url: directory.appendingPathComponent("\(index)-\(id).\(isImage ? "img" : "asif")"), isImage: isImage)
            guard names.contains(file.url.lastPathComponent) else {
                throw CLIError.failure("layer \(bundle.lastPathComponent) is damaged: \(file.url.lastPathComponent) is missing")
            }
            files.append(file)
        }
        return files
    }
}

/// The reservation of a layer's name by the VM that will save it (`--save`, `--clone`, or `--continue`): an advisory `flock(2)`
/// on `.NAME.layer.lock` beside the target, held by the VM's process for the life of the VM. The kernel releases it when the
/// process dies, so a crash leaves nothing stale.
enum LayerLock {
    static func file(for target: URL) -> URL {
        target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).lock")
    }

    /// Takes the lock, or says which layer is already the target of another VM. The descriptor stays open until `release`.
    static func acquire(_ target: URL) throws -> Int32 {
        let path = file(for: target).path
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw CLIError.failure("cannot reserve \(target.lastPathComponent): \(String(cString: strerror(errno)))") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw CLIError.failure("\(target.lastPathComponent) is already the target of another VM: wait for it to stop, or name another layer")
        }
        return fd
    }

    /// Whether the name is free to reserve, without holding it.
    static func isFree(_ target: URL) -> Bool {
        guard let fd = try? acquire(target) else { return false }
        release(fd, target)
        return true
    }

    static func release(_ fd: Int32, _ target: URL) {
        unlink(file(for: target).path)
        close(fd)
    }
}
