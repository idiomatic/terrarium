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

public func note(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
