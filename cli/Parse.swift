import Foundation
import TerrariumCore

/// Parses the arguments after the verb. Throws `.usage` on any mistake.
func parse(_ verb: Verb, _ argv: [String]) throws -> Invocation {
    var inv = Invocation(verb: verb)
    var positional = 0
    var literal = false
    var i = 0
    while i < argv.count {
        let arg = argv[i]
        i += 1
        if !literal && arg == "--" {
            literal = true
        } else if !literal && (arg == "-h" || arg == "--help") {
            throw CLIError.help
        } else if !literal && arg.hasPrefix("--") {
            let body = arg.dropFirst(2)
            let eq = body.firstIndex(of: "=")
            let name = String(eq.map { body[..<$0] } ?? body)
            let inline = eq.map { String(body[body.index(after: $0)...]) }
            if name == "vm" && verb.targetsVM {
                inv.values["vm"] = try inline ?? next(argv, &i, "--vm")
                continue
            }
            guard let opt = verb.options.first(where: { $0.name == name || $0.aliases.contains(name) }) else {
                throw CLIError.usage("unknown option --\(name)")
            }
            guard opt.metavar != nil else {
                if inline != nil { throw CLIError.usage("--\(name) takes no value") }
                inv.flags.insert(opt.name)
                continue
            }
            let value = try inline ?? next(argv, &i, "--\(name)")
            try checkValue(value, opt.kind, "--\(name)")
            if opt.repeatable { inv.lists[opt.name, default: []].append(value) } else { inv.values[opt.name] = value }
        } else if positional < verb.positionals.count {
            let p = verb.positionals[positional]
            positional += 1
            try checkValue(arg, p.kind, p.metavar)
            if p.name == "chord" { try checkChord(arg) }
            inv.values[p.name] = arg
            if positional == verb.positionals.count && verb.passthrough != nil { literal = true }
        } else if verb.passthrough != nil {
            inv.rest.append(arg)
        } else {
            throw CLIError.usage("unexpected argument '\(arg)'")
        }
    }
    if positional < verb.positionals.count, !verb.positionals[positional...].allSatisfy(\.optional) {
        throw CLIError.usage("missing \(verb.positionals[positional].metavar)")
    }
    return inv
}

private func next(_ argv: [String], _ i: inout Int, _ option: String) throws -> String {
    guard i < argv.count else { throw CLIError.usage("\(option) needs a value") }
    defer { i += 1 }
    return argv[i]
}
