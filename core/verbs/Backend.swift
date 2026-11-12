import Foundation

public enum Output {
    case none
    /// Exit with this status, after anything already written.
    case status(Int32)
    case text(String)
    /// Written as is, with no newline added.
    case raw(String)
    case png(Data)
}

/// Runs a parsed verb; one the table does not handle is reported as not implemented.
public enum Backend {
    /// Makes the window that `run` shows; the front-end sets it. Without one, `run` fails.
    public nonisolated(unsafe) static var windowFactory: OwnerUIFactory?

    /// Clears what a process that died left behind: partial downloads and attached images; and retired cache files.
    public static func sweep() {
        Store.sweepPartials()
        Attached.sweep()
        Recipe.sweepRetiredBlankDisks()
    }

    /// `ps` for a caller that started VMs as `by`: the table, its own marked, and each VM as a record with `mine`.
    public static func ps(by: String) -> (table: String, vms: [[String: Any]]) {
        let iso = ISO8601DateFormatter()
        let stored = (try? Store.list()) ?? []
        let vms: [[String: Any]] = Runtime.list().map {
            ["id": $0.id, "image": Store.displayName($0.image, among: stored), "by": $0.by ?? NSNull(), "mine": $0.by == by, "state": $0.state,
             "display": $0.display ?? NSNull(), "window": $0.windowed, "started": iso.string(from: $0.started)]
        }
        return (Runtime.table(mine: by), vms)
    }

    public static func perform(_ inv: Invocation) throws -> Output {
        switch inv.verb.name {
        case "pull":
            return .text(try Pull.run(source: inv.values["source"]!))
        case "images":
            Store.sweepPartials()
            return .text(try Store.table())
        case "layers":
            return .text(try LayerVerbs.table())
        case "rm":
            return .text(try LayerVerbs.remove(inv.values["layer"]!))
        case "squash":
            return .text(try Squash.run(inv))
        case "start":
            return .text(try Launch.start(inv))
        case "run":
            try Launch.run(inv)
        case "commit":
            return .text(try Launch.commit(inv))
        case "stop":
            return .text(try Launch.stop(inv.values["vm"]!))
        case "ps":
            return .text(inv.flags.contains("deceased") ? Runtime.deceasedTable() : Runtime.table())
        case "shot", "logs", "click", "move", "resize", "type", "key", "exec", "tweak", "clipboard", "wait", "put", "get":
            return try Remote.perform(inv)
        case "rmi":
            let image = try Store.resolve(inv.values["image"]!)
            try FileManager.default.removeItem(at: image.url)
            return .text(image.name)
        default:
            throw CLIError.notImplemented(inv.verb.name)
        }
    }
}
