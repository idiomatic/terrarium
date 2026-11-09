import Foundation

/// What `start` and `run` were asked to boot.
struct BootRequest {
    /// Nil for an installed overlay, which needs no image.
    var image: Store.Image?
    var overlay: URL?
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
    /// `run --commit-on-stop PATH`: the prefix to save the overlay under when the VM stops.
    var commitOnStop: URL?
    /// The tweaks (`<os>/<name>`) to run once the helper answers, in order.
    var tweaks: [String] = []
    /// The manifest of the installed overlay being booted.
    var installed: GuestManifest?
    /// The installed guest an `--overlay` lies over; `overlay` is then that layer, not the guest.
    var guest: URL?

    /// Whether the VM is saved as an installed guest, and the name its save is keyed by (see `Owner.saveTarget`).
    var savesGuest: Bool { guest == nil && (installed != nil || recipe?.isInstall == true) }
    var saveKey: String { (guest != nil ? installed?.id : nil) ?? image?.name ?? installed?.installer ?? "-" }
}
