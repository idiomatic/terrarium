import Foundation
import Virtualization

/// What the overlay layer looked like at a point in time: it changes when the guest writes to its disk.
struct LayerStamp: Equatable {
    var modified: Date
    var size: UInt64
}

/// Saving a VM's overlay: now, or when it stops.
extension Owner {
    func layerStamp() -> LayerStamp? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(MacFiles.layer).path),
              let modified = attributes[.modificationDate] as? Date, let size = attributes[.size] as? UInt64 else { return nil }
        return LayerStamp(modified: modified, size: size)
    }

    /// Whether the guest has written to its disk since the VM started or was last committed (what the guest has flushed).
    public var changedSinceCommit: Bool { layerStamp() != committedStamp }

    /// What `--install` leaves, or a guest booted without `--overlay`, is an installed guest, `<prefix>.guest`: complete on
    /// its own. Any other overlay is a layer over its image, `<prefix>-<imagehash>.overlay`, or over a guest,
    /// `<prefix>-<guestid>.overlay`.
    public var savesInstalledOverlay: Bool { plan.installed }

    public func overlayTarget(_ prefix: URL) -> URL {
        Owner.saveTarget(prefix, installed: savesInstalledOverlay, image: plan.guestID ?? info.image)
    }

    static func saveTarget(_ prefix: URL, installed: Bool, image: String) -> URL {
        installed
            ? URL(fileURLWithPath: prefix.path + GuestManifest.suffix)
            : URL(fileURLWithPath: "\(prefix.path)-\(image.suffix(16)).overlay")
    }

    /// Fails early when a save could not succeed: the target exists or its directory does not.
    public func checkSaveTarget(_ prefix: URL) throws {
        try Owner.checkSaveTarget(overlayTarget(prefix))
    }

    static func checkSaveTarget(_ target: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.deletingLastPathComponent().path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CLIError.failure("no such directory: \(target.deletingLastPathComponent().path)")
        }
        guard !FileManager.default.fileExists(atPath: target.path) else { throw CLIError.failure("\(target.path) already exists") }
    }

    /// Checks the target and gathers what to copy, on the main queue; the job it returns copies, on any thread, and removes
    /// what it made if the copy fails. The VM must be paused or stopped while it runs, so the copy is a single point in time.
    func overlayCopy(to prefix: URL) throws -> () throws -> URL {
        try checkSaveTarget(prefix)
        let target = overlayTarget(prefix)
        let installed = savesInstalledOverlay
        // An overlay over a macOS guest is a directory too: its layer and the auxiliary storage, the rest being the guest's.
        let overGuest = plan.guestID != nil
        let names = plan.kind != .macos ? [MacFiles.layer] : overGuest ? [MacFiles.layer, MacFiles.auxiliaryStorage] : MacFiles.all
        let manifest = GuestManifest(guest: GuestManifest.name(of: plan.kind), diskGB: plan.diskGB, installer: info.image, id: GuestManifest.newID())
        let directory = directory
        return {
            do {
                if installed || (overGuest && names.count > 1) {
                    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
                    for name in names { try Pull.cloneOrCopy(directory.appendingPathComponent(name), to: target.appendingPathComponent(name)) }
                    if installed { try manifest.write(to: target) }
                } else {
                    try Pull.cloneOrCopy(directory.appendingPathComponent(MacFiles.layer), to: target)
                }
            } catch {
                try? FileManager.default.removeItem(at: target)
                throw error
            }
            return target
        }
    }

    /// Copies the overlay now, on this thread: for a VM that has stopped.
    func copyOverlay(to prefix: URL) throws -> URL {
        try overlayCopy(to: prefix)()
    }

    /// Saves the overlay now: pauses the VM (unless it is paused already), copies the layer off the main queue, and resumes.
    /// What the guest has not flushed to its disk is not in the copy. A stop asked for meanwhile waits for the copy.
    public func saveOverlay(to prefix: URL, then done: @escaping (Result<URL, Error>) -> Void) {
        let job: () throws -> URL
        do { job = try overlayCopy(to: prefix) } catch { return done(.failure(error)) }
        guard !committing else { return done(.failure(CLIError.failure("a commit is already running"))) }
        let wasPaused = vm.state == .paused
        guard wasPaused || vm.canPause else { return done(.failure(CLIError.failure("the VM is not running"))) }
        committing = true
        transient = "committing…"
        let finished = { [self] (saved: Result<URL, Error>) in
            committing = false
            transient = nil
            done(saved)
            if let stop = stopAfterCommit {
                stopAfterCommit = nil
                stopAndExit(reply: stop)
            }
        }
        let copy = { [self] in
            DispatchQueue.global().async {
                let saved = Result { try job() }
                DispatchQueue.main.async { [self] in
                    if case .success = saved { committedStamp = layerStamp() }
                    if wasPaused { return finished(saved) }
                    vm.resume { _ in finished(saved) }
                }
            }
        }
        if wasPaused { return copy() }
        vm.pause { [self] paused in
            if case .failure(let error) = paused {
                committing = false
                transient = nil
                return done(.failure(error))
            }
            copy()
        }
    }
}
