import Foundation

/// Where terrarium keeps what it keeps: the support directory and what is in it. The front-end sets `support` once, at
/// startup, before it calls anything else in the core; the core never reads the environment.
public enum Paths {
    /// `~/Library/Application Support/terrarium`.
    public static let standardSupport = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/terrarium", isDirectory: true)

    /// The support directory. A front-end replaces it before use (the CLI reads `$TERRARIUM_SUPPORT`, as the tests do).
    public nonisolated(unsafe) static var support = standardSupport

    /// The image store.
    static var images: URL { child("images") }
    /// Each running VM's state, `vms/<id>/`.
    static var vms: URL { child("vms") }
    /// Downloaded and built media that recipes reuse.
    static var cache: URL { child("cache") }
    /// Records of attached disk images, ejected at startup when their process is gone.
    static var attached: URL { child("attached") }
    /// A record of each of the last few VMs that ended, `deceased/<id>.json`.
    static var deceased: URL { child("deceased") }
    /// The files of VMs whose scheduled commit failed, `unsaved/<id>/`.
    static var unsaved: URL { child("unsaved") }

    private static func child(_ name: String) -> URL { support.appendingPathComponent(name, isDirectory: true) }
}
