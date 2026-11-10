import Foundation
import TerrariumCore

private func usageLine(_ v: Verb) -> String {
    let options = v.options.map { "[--\($0.name)\($0.metavar.map { " \($0)" } ?? "")]" }
    let positionals = v.positionals.map { $0.optional ? "[\($0.metavar)]" : $0.metavar } + (v.passthrough.map { ["[\($0)...]"] } ?? [])
    // Options come first when the arguments after the last positional are taken verbatim.
    let parts = v.passthrough == nil ? positionals + options : options + positionals
    return (["terrarium", v.name] + parts).joined(separator: " ")
}

private func column(_ rows: [(String, String)]) -> String {
    let width = rows.map { $0.0.count }.max() ?? 0
    return rows.map { "  " + $0.0.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + $0.1 }.joined(separator: "\n")
}

func overview() -> String {
    var out = "usage: terrarium VERB [ARGS...]\n\nDrives macOS, Linux, and Windows guests. Each verb except run is also an MCP tool.\n"
    for g in verbGroups {
        out += "\n\(g.title):\n" + column(g.verbs.map { ($0.name, $0.summary) }) + "\n"
    }
    out += "\nterrarium mcp serves the verbs (except run) as MCP tools on stdin and stdout.\n"
    out += "terrarium help VERB shows a verb's arguments; terrarium version (or --version) shows the version.\n"
    return out
}

func help(for v: Verb) -> String {
    var out = "usage: \(usageLine(v))\n\n\(v.summary)\n"
    var rows = v.positionals.map { ($0.metavar, $0.help) }
    rows += v.options.map { ("--\($0.name)\($0.metavar.map { " \($0)" } ?? "")", $0.help) }
    if let p = v.passthrough { rows.append((p, "passed to COMMAND unchanged")) }
    if !rows.isEmpty { out += "\n" + column(rows) + "\n" }
    return out
}
