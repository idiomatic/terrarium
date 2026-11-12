import Foundation

/// What `start` and `run` were asked to boot.
struct BootRequest {
    /// A stored image: the root of the new layer's chain, or an installer for `--install`. Nil for a layer.
    var image: Store.Image?
    /// The layer (a `NAME.layer` bundle) to boot, and its manifest.
    var layer: URL?
    var manifest: LayerManifest?
    /// `--clone` or `--continue`: the VM's delta starts as a copy of the layer's own, so a save is its sibling, not its child.
    var keepDelta = false
    /// `--ephemeral`: the VM's work is discarded when it stops, unless committed meanwhile.
    var ephemeral = false
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
    /// `--save`, `--clone`, or `--continue`: the layer to save when the VM stops.
    var commitOnStop: URL?
    /// The tweaks (`<os>/<name>`) to run once the helper answers, in order.
    var tweaks: [String] = []
    /// `--by`: who started the VM, a label `ps` shows.
    var by = "cli"

    /// What `ps` calls what the VM started from: the image's name, or the layer's name or path.
    var startedFrom: String { image?.name ?? layer.map(Self.display) ?? "-" }

    static func display(_ layer: URL) -> String {
        layer.deletingLastPathComponent().standardizedFileURL == Paths.layers.standardizedFileURL
            ? layer.deletingPathExtension().lastPathComponent : layer.path
    }
}
