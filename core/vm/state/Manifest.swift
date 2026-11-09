import Foundation

/// An installed overlay is what `--install` (`windows`, `macos`, `alpine`) leaves after `commit`: a directory holding the disk
/// layer, any identity files the guest needs, and this manifest. It boots with no stored image, over a blank disk of
/// `diskGB` that terrarium regenerates.
struct GuestManifest: Codable {
    static let fileName = "manifest.json"
    static let suffix = ".guest"

    var version = 1
    /// `windows`, `macos`, or `linux`.
    var guest: String
    var diskGB: Int
    /// The installer image it was installed from, kept as provenance.
    var installer: String
    /// Names the guest for the overlays made over it (`PATH-<id>.overlay`); chosen at `commit`. A guest saved before this has none.
    var id: String?

    static func newID() -> String { String(format: "%016llx", UInt64.random(in: .min ... .max)) }

    /// The manifest of an installed overlay, or nil when `overlay` is a plain layer file.
    static func read(_ overlay: URL) -> GuestManifest? {
        guard let data = try? Data(contentsOf: overlay.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(GuestManifest.self, from: data)
    }

    func write(to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: directory.appendingPathComponent(Self.fileName))
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
