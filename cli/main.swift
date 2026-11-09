import Foundation
import TerrariumCore
import TerrariumUI

// The support directory: `$TERRARIUM_SUPPORT` (the tests use a temporary one), else the standard one.
if let path = ProcessInfo.processInfo.environment["TERRARIUM_SUPPORT"], !path.isEmpty {
    Paths.support = URL(fileURLWithPath: path, isDirectory: true)
}
Backend.windowFactory = makeRunWindow

func fail(_ message: String, code: Int32) -> Int32 {
    FileHandle.standardError.write(Data("terrarium: \(message)\n".utf8))
    return code
}

func run(_ args: [String]) -> Int32 {
    if let verb = args.first, verb != "help", !verb.hasPrefix("-") { Backend.sweep() }
    guard let first = args.first else {
        FileHandle.standardError.write(Data(overview().utf8))
        return 2
    }
    if first == "-h" || first == "--help" {
        print(overview(), terminator: "")
        return 0
    }
    if first == "help" {
        guard let name = args.dropFirst().first else {
            print(overview(), terminator: "")
            return 0
        }
        guard let verb = findVerb(name) else { return fail("unknown verb '\(name)'", code: 2) }
        print(help(for: verb), terminator: "")
        return 0
    }
    if first == "mcp" {
        // The MCP server on stdio; stdout carries only protocol messages.
        MCPServer().run()
    }
    if first == "__serve" {
        // Internal: the detached owner process that `start` spawns.
        do {
            try Launch.serve(args)
        } catch {
            return fail((error as? CLIError)?.message ?? "\(error)", code: 1)
        }
    }
    guard let verb = findVerb(first) else {
        return fail("unknown verb '\(first)'; see 'terrarium help'", code: 2)
    }
    do {
        var inv = try parse(verb, Array(args.dropFirst()))
        if verb.name == "clipboard", inv.values["action"] == "set", inv.values["text"] == "-" {
            // Standard input, here and not in the core: the MCP server's standard input carries its requests.
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else { return fail("standard input is not valid UTF-8", code: 1) }
            inv.values["text"] = text
        }
        let output = try Backend.perform(inv)
        switch output {
        case .none:
            break
        case .status(let code):
            return HelperProtocol.processStatus(code)
        case .text(let s):
            if !s.isEmpty { print(s) }
        case .raw(let s):
            FileHandle.standardOutput.write(Data(s.utf8))
        case .png(let data):
            if isatty(STDOUT_FILENO) != 0 { return fail("not writing a PNG to a terminal; redirect stdout", code: 1) }
            FileHandle.standardOutput.write(data)
        }
        return 0
    } catch CLIError.help {
        print(help(for: verb), terminator: "")
        return 0
    } catch CLIError.usage(let message) {
        return fail("\(message)\n\n" + help(for: verb), code: 2)
    } catch CLIError.notImplemented(let name) {
        return fail("'\(name)' is not implemented yet", code: 70)
    } catch CLIError.failure(let message) {
        return fail(message, code: 1)
    } catch {
        return fail("\(error)", code: 1)
    }
}

exit(run(Array(CommandLine.arguments.dropFirst())))
