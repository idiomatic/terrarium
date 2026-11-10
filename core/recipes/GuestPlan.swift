import Foundation

extension LayerManifest {
    /// Clones the whole layer bundle into `pinned/layer` in the VM's directory, in one `clonefile(2)` call, so that the VM's
    /// manifest and files are one point in time and replacing the layer meanwhile (a `--continue` VM stopping) changes nothing
    /// this VM reads, commits, or reopens after a restart. Nil when it cannot be cloned (the layer is on another volume): the
    /// VM then uses the layer in place, since copying a layer could take minutes.
    static func snapshot(_ bundle: URL, in directory: URL) -> URL? {
        let pinned = directory.appendingPathComponent(Plan.pinnedDirectory, isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: pinned, withIntermediateDirectories: true)) != nil else { return nil }
        let copy = pinned.appendingPathComponent("layer", isDirectory: true)
        return clonefile(bundle.path, copy.path, 0) == 0 ? copy : nil
    }
}

extension Plan {
    static let pinnedDirectory = "pinned"
}

extension LayerManifest {
    /// The plan for booting the layer at `bundle`: its kind, over its chain. The chain starts at an image or at a blank disk of
    /// `diskGB` that terrarium regenerates. The layer's own delta is the last file of the chain, or, with `keepDelta`, the one
    /// the VM's starts as a copy of.
    func plan(bundle: URL, keepDelta: Bool, in directory: URL) throws -> Plan {
        var files = try LayerStore.chainFiles(of: bundle, self)
        let delta = bundle.appendingPathComponent(Self.deltaFile)
        let base = files.first?.isImage == true ? files[0].url : try Recipe.blankDisk(gigabytes: diskGB, in: directory)
        if !keepDelta { files.append(ChainFile(id: id, url: delta, isImage: false)) }
        var plan = Plan(kind: kind, baseDisk: base, mac: kind == .macos ? MacPlan() : nil, diskGB: diskGB)
        plan.chain = files
        plan.keepDelta = keepDelta ? delta : nil
        plan.source = bundle
        return plan
    }
}
