import Foundation

/// A parsed command line: values by parameter or option name, flags, and passthrough arguments.
public struct Invocation {
    public let verb: Verb
    public var values: [String: String] = [:]
    public var flags: Set<String> = []
    /// The values of repeatable options, in the order given.
    public var lists: [String: [String]] = [:]
    public var rest: [String] = []

    public init(verb: Verb) { self.verb = verb }

    public func point(_ name: String) -> (x: Int, y: Int)? {
        guard let v = values[name] else { return nil }
        let p = v.split(separator: ",").compactMap { Int($0) }
        return p.count == 2 ? (p[0], p[1]) : nil
    }
}

public func checkValue(_ value: String, _ kind: Kind, _ label: String) throws {
    switch kind {
    case .text:
        break
    case .integer:
        guard let n = Int(value), n > 0 else { throw CLIError.usage("\(label): expected a positive whole number, got '\(value)'") }
    case .point:
        let p = value.split(separator: ",", omittingEmptySubsequences: false)
        guard p.count == 2, p.allSatisfy({ Int($0) != nil }) else {
            throw CLIError.usage("\(label): expected two integers like 10,20, got '\(value)'")
        }
    case .choice(let allowed):
        guard allowed.contains(value) else {
            throw CLIError.usage("\(label): expected one of \(allowed.joined(separator: ", ")), got '\(value)'")
        }
    }
}

public func checkChord(_ chord: String) throws {
    let parts = chord.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
    guard let key = parts.last, !key.isEmpty else { throw CLIError.usage("chord: missing key in '\(chord)'") }
    for m in parts.dropLast() where !chordModifiers.contains(m) {
        throw CLIError.usage("chord: unknown modifier '\(m)' (use \(chordModifiers.sorted().joined(separator: ", ")))")
    }
}

/// Builds an invocation from named arguments (an MCP `tools/call`), with the checks the command line gets.
/// Names are the parameters' and options' own, `vm` for the target VM, and `args` for passthrough arguments.
public func invocation(_ verb: Verb, arguments: [String: Any]) throws -> Invocation {
    func isBool(_ value: Any) -> Bool { (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false }
    func text(_ value: Any, _ name: String) throws -> String {
        if let string = value as? String { return string }
        if !isBool(value), let number = value as? Int { return String(number) }
        throw CLIError.usage("\(name): expected a string or whole number")
    }
    var inv = Invocation(verb: verb)
    var unknown = Set(arguments.keys)
    for p in verb.positionals {
        unknown.remove(p.name)
        guard let value = arguments[p.name] else {
            if p.optional { continue }
            throw CLIError.usage("missing \(p.name)")
        }
        let string = try text(value, p.name)
        try checkValue(string, p.kind, p.name)
        if p.name == "chord" { try checkChord(string) }
        inv.values[p.name] = string
    }
    for o in verb.options {
        guard let value = arguments[o.name] else { continue }
        unknown.remove(o.name)
        if o.metavar == nil {
            guard isBool(value), let on = value as? Bool else { throw CLIError.usage("\(o.name): expected true or false") }
            if on { inv.flags.insert(o.name) }
        } else if o.repeatable {
            guard let list = value as? [Any] else { throw CLIError.usage("\(o.name): expected a list of strings") }
            inv.lists[o.name] = try list.map { try text($0, o.name) }
        } else {
            let string = try text(value, o.name)
            try checkValue(string, o.kind, o.name)
            inv.values[o.name] = string
        }
    }
    if verb.targetsVM, let value = arguments["vm"] {
        unknown.remove("vm")
        inv.values["vm"] = try text(value, "vm")
    }
    if verb.passthrough != nil, let value = arguments["args"] {
        unknown.remove("args")
        guard let list = value as? [Any] else { throw CLIError.usage("args: expected a list of strings") }
        inv.rest = try list.map { try text($0, "args") }
    }
    if let extra = unknown.sorted().first { throw CLIError.usage("unknown argument '\(extra)'") }
    return inv
}
