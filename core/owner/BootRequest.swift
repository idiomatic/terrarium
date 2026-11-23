import Foundation

/// What becomes of a VM's work, as `start` and `run` are told: nothing said (`run` asks when its window closes), discarded
/// (`--ephemeral`, unless committed meanwhile), or saved when the VM stops as a child of what it started from (`--save`),
/// as a sibling of its layer (`--clone`), or over its layer (`--continue`).
enum SaveChoice: Equatable {
    case unsaid
    case ephemeral
    case child(URL)
    case sibling(URL)
    case continues(URL)

    /// The layer to save when the VM stops.
    var target: URL? {
        switch self {
        case .unsaid, .ephemeral: nil
        case .child(let url), .sibling(let url), .continues(let url): url
        }
    }

    /// Whether the VM's delta starts as a copy of its layer's own, so a save is that layer's sibling, not its child.
    var keepsDelta: Bool {
        switch self {
        case .sibling, .continues: true
        case .unsaid, .ephemeral, .child: false
        }
    }
}

/// What `start` and `run` were asked to boot.
struct BootRequest {
    /// A stored image: the root of the new layer's chain, or an installer for `--install`. Nil for a layer.
    var image: Store.Image?
    /// The layer (a `NAME.layer` bundle) to boot, and its manifest.
    var layer: URL?
    var manifest: LayerManifest?
    /// What becomes of the VM's work.
    var save = SaveChoice.unsaid
    var recipe: Recipe?
    var resources: Resources
    /// The account to create; nil is Windows' `terra` or, on macOS, none.
    var user: String?
    /// The Windows account's password; nil makes a random one.
    var password: String?
    /// `--disk GB`: an install's target disk size; nil is the recipe's default.
    var diskGB: Int?
    /// The caller's agreement to the vendor's license, given per install.
    var acceptLicense = false
    /// The tweaks (`<os>/<name>`) to run once the helper answers, in order.
    var tweaks: [String] = []
    /// `--by`: who started the VM, a label `ps` shows.
    var by = "cli"
    /// `--network NAME[:KEY]`: the named networks to join, each with the VM's KEY on it.
    var networks: [(name: String, key: String)] = []

    /// What `ps` calls what the VM started from: the image's name, or the layer's name or path.
    var startedFrom: String { image?.name ?? layer.map(Self.display) ?? "-" }

    static func display(_ layer: URL) -> String {
        layer.deletingLastPathComponent().standardizedFileURL == Paths.layers.standardizedFileURL
            ? layer.deletingPathExtension().lastPathComponent : layer.path
    }
}
