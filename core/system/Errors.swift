import Foundation

/// What every verb and the code under it throws: a usage mistake or a failure with a message for the user.
public enum CLIError: Error {
    case help
    case usage(String)
    case failure(String)
    case notImplemented(String)
}

extension CLIError {
    public var message: String {
        switch self {
        case .help: return "help requested"
        case .usage(let text), .failure(let text): return text
        case .notImplemented(let name): return "'\(name)' is not implemented yet"
        }
    }
}
