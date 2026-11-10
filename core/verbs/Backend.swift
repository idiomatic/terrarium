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

    public static func perform(_ inv: Invocation) throws -> Output {
        switch inv.verb.name {
        case "pull":
            return .text(try Pull.run(source: inv.values["source"]!))
        case "images":
            Store.sweepPartials()
            return .text(try Store.table())
        case "start":
            return .text(try Launch.start(inv))
        case "run":
            try Launch.run(inv)
        case "commit":
            return .text(try Launch.commit(inv))
        case "stop":
            return .text(try Launch.stop(inv.values["id"]!))
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
