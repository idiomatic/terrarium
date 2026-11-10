import Foundation
import Virtualization

/// What the VM's delta looked like at a point in time: it changes when the guest writes to its disk.
struct LayerStamp: Equatable {
    var modified: Date
    var size: UInt64
}

/// Saving a VM's delta as a layer: now, or when it stops.
extension Owner {
    func layerStamp() -> LayerStamp? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(MacFiles.layer).path),
              let modified = attributes[.modificationDate] as? Date, let size = attributes[.size] as? UInt64 else { return nil }
        return LayerStamp(modified: modified, size: size)
    }

    /// Whether the guest has written to its disk since the VM started or was last committed (what the guest has flushed).
    public var changedSinceCommit: Bool { layerStamp() != committedStamp }

    /// The layer store, where a front-end offers to save a layer, made if it is missing.
    public static var layerStoreDirectory: URL {
        try? FileManager.default.createDirectory(at: Paths.layers, withIntermediateDirectories: true)
        return Paths.layers
    }

    /// The bundle a path chosen in a front-end saves to (`.layer` is added).
    public static func layerLocation(_ path: String) -> URL { LayerStore.location(path) }

    /// Whether what the VM saves is a root layer: what `--install` leaves, whole on its own.
    public var savesRoot: Bool { plan.installed }

    /// Fails early when a save could not succeed: the target exists (unless it is the layer a `--clone` or `--continue` VM started from,
    /// which a save replaces) or its directory does not.
    public func checkSaveTarget(_ target: URL) throws {
        try Owner.checkSaveTarget(target, startedFrom: plan.keepDelta != nil ? plan.source : nil)
    }

    static func checkSaveTarget(_ target: URL, startedFrom: URL?) throws {
        let parent = target.deletingLastPathComponent()
        if parent.standardizedFileURL == Paths.layers.standardizedFileURL {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CLIError.failure("no such directory: \(parent.path)")
        }
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        guard startedFrom?.standardizedFileURL == target.standardizedFileURL else { throw CLIError.failure("\(target.path) already exists") }
    }

    /// Checks the target and gathers what to clone, on the main queue; the job it returns clones, on any thread, into a bundle
    /// beside the target and moves it into place (a replaced layer is swapped out), and removes what it made if that fails. The
    /// VM must be paused or stopped while it runs, so the delta is a single point in time.
    func layerCopy(to target: URL) throws -> () throws -> URL {
        try checkSaveTarget(target)
        let replacing = FileManager.default.fileExists(atPath: target.path)
        // A VM continuing a layer that has been moved or removed would recreate it under its old name.
        if !replacing, plan.keepDelta != nil, plan.source?.standardizedFileURL == target.standardizedFileURL {
            throw CLIError.failure("\(target.lastPathComponent) is gone: it was moved or removed since this VM started from it")
        }
        let manifest = LayerManifest(guest: LayerManifest.name(of: plan.kind), diskGB: plan.diskGB, installer: provenance, id: LayerManifest.newID(), chain: plan.chain.map(\.id))
        let chain = plan.chain
        let startedID = startedID
        let kind = plan.kind
        let directory = directory
        return {
            let manager = FileManager.default
            let partial = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).partial.\(getpid())", isDirectory: true)
            try? manager.removeItem(at: partial)
            do {
                try manager.createDirectory(at: partial.appendingPathComponent(LayerManifest.chainDirectory), withIntermediateDirectories: true)
                for (index, file) in chain.enumerated() {
                    try Pull.cloneOrCopy(file.url, to: partial.appendingPathComponent(LayerManifest.chainDirectory).appendingPathComponent(file.name(at: index)))
                }
                try Pull.cloneOrCopy(directory.appendingPathComponent(MacFiles.layer), to: partial.appendingPathComponent(LayerManifest.deltaFile))
                // A macOS guest's identity files and auxiliary storage are one machine with its delta.
                if kind == .macos {
                    for name in [MacFiles.auxiliaryStorage, MacFiles.hardwareModel, MacFiles.machineIdentifier] {
                        try Pull.cloneOrCopy(directory.appendingPathComponent(name), to: partial.appendingPathComponent(name))
                    }
                }
                try manifest.write(to: partial)
                if replacing {
                    guard (try? LayerManifest.read(target))?.id == startedID else {
                        throw CLIError.failure("\(target.lastPathComponent) was replaced since this VM started from it")
                    }
                    guard renamex_np(partial.path, target.path, UInt32(RENAME_SWAP)) == 0 else {
                        throw CLIError.failure("cannot replace \(target.path): \(String(cString: strerror(errno)))")
                    }
                    // The swap left the old layer at `partial`.
                    try? manager.removeItem(at: partial)
                } else {
                    guard renamex_np(partial.path, target.path, UInt32(RENAME_EXCL)) == 0 else {
                        throw CLIError.failure(errno == EEXIST ? "\(target.path) already exists" : "cannot save \(target.path): \(String(cString: strerror(errno)))")
                    }
                }
            } catch {
                try? manager.removeItem(at: partial)
                throw error
            }
            return target
        }
    }

    /// Saves the delta now, on this thread: for a VM that has stopped.
    func copyLayer(to target: URL) throws -> URL {
        try layerCopy(to: target)()
    }

    /// Saves the delta now: pauses the VM (unless it is paused already), clones the files off the main queue, and resumes.
    /// What the guest has not flushed to its disk is not in the copy. A stop asked for meanwhile waits for the copy.
    public func saveLayer(to target: URL, then done: @escaping (Result<URL, Error>) -> Void) {
        let job: () throws -> URL
        do { job = try layerCopy(to: target) } catch { return done(.failure(error)) }
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
