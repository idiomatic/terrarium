import Foundation

/// Runs a stock macOS program to completion and returns its standard output.
/// Standard output goes to `output` instead when given; `environment` is added to this process's, and `input` is the
/// program's standard input (empty by default).
@discardableResult
func runProgram(_ path: String, _ arguments: [String], output: FileHandle? = nil, environment: [String: String] = [:],
                input: Data = Data()) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    if !environment.isEmpty { process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 } }
    let out = Pipe()
    let err = Pipe()
    let stdin = Pipe()
    process.standardInput = stdin
    process.standardOutput = output ?? out
    process.standardError = err
    try process.run()
    // The read ends are this process's to close (nothing drains an autorelease pool during a VM's boot, so they would
    // stay open); a program that exits before reading its input must not raise an exception here.
    defer {
        try? out.fileHandleForReading.close()
        try? err.fileHandleForReading.close()
    }
    try? stdin.fileHandleForWriting.write(contentsOf: input)
    try? stdin.fileHandleForWriting.close()
    var errorData = Data()
    let reader = DispatchGroup()
    DispatchQueue.global().async(group: reader) { errorData = err.fileHandleForReading.readDataToEndOfFile() }
    let outData = output == nil ? out.fileHandleForReading.readDataToEndOfFile() : Data()
    reader.wait()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let text = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        throw CLIError.failure("\(URL(fileURLWithPath: path).lastPathComponent) failed (exit \(process.terminationStatus))" + (text.isEmpty ? "" : ": \(text)"))
    }
    return outData
}

/// The last line `note` wrote, for what says why a VM ended.
nonisolated(unsafe) public private(set) var lastNote = ""

public func note(_ message: String) {
    lastNote = message.split(separator: "\n").last.map(String.init) ?? message
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// Spawns this executable in its own session with output to `log`, so it outlives the terminal and this process.
func spawnDetached(_ arguments: [String], log: URL) throws -> pid_t {
    var actions: posix_spawn_file_actions_t? = nil
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_addopen(&actions, 1, log.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
    posix_spawn_file_actions_adddup2(&actions, 1, 2)
    var attributes: posix_spawnattr_t? = nil
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    // Only the descriptors set up above: an MCP server's pipes to other calls' programs must not stay open in a VM's process.
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

    guard let executable = Bundle.main.executablePath else { throw CLIError.failure("cannot find the terrarium executable") }
    let argv = ([executable] + arguments).map { strdup($0) } + [nil]
    defer { argv.forEach { free($0) } }
    var pid: pid_t = 0
    let status = posix_spawn(&pid, executable, &actions, &attributes, argv, environ)
    guard status == 0 else { throw CLIError.failure("cannot start a terrarium process: \(String(cString: strerror(status)))") }
    return pid
}
