import Foundation
import Virtualization

/// How a `setClipboard` reached the guest.
public enum ClipboardPath {
    /// Through the guest's clipboard, by its helper.
    case helper
    /// Typed on the guest's keyboard, because the guest has no clipboard to use.
    case typed
}

/// Moving text through the guest's clipboard, as the `clipboard` verb and the window's Edit menu do.
extension Owner {
    /// The most text that is typed in place of a clipboard.
    static let typeLimit = 4 << 10

    private static func message(_ error: Error) -> CLIError {
        switch error {
        case let error as CLIError: return error
        case HelperProtocol.ClipboardFailure.unavailable: return .failure("the guest has no clipboard")
        case HelperProtocol.ClipboardFailure.failed(let text): return .failure(text)
        default: return .failure("\(error)")
        }
    }

    /// Connects to the guest's helper once; nil when it is not reachable. Call it on the main queue.
    private func connectOnce(_ done: @escaping (VZVirtioSocketConnection?) -> Void) {
        guard let device = vm.socketDevices.first as? VZVirtioSocketDevice else { return done(nil) }
        device.__connect(toPort: HelperProtocol.port) { connection, _ in done(connection) }
    }

    /// The guest's clipboard text, delivered on the main queue.
    public func getClipboard(_ done: @escaping (Result<String, CLIError>) -> Void) {
        connectOnce { connection in
            guard let connection else {
                return done(.failure(.failure("the guest's helper is not reachable (vsock port \(HelperProtocol.port)); is it running?")))
            }
            DispatchQueue.global().async {
                let result = Result { try HelperProtocol.fetchClipboard(over: connection) }.mapError(Owner.message)
                DispatchQueue.main.async { done(result) }
            }
        }
    }

    /// Replaces the guest's clipboard text, delivered on the main queue. A guest with no clipboard (no helper yet, or none
    /// in its session) gets the text typed instead when `typing` allows, if it is US ASCII and short enough.
    public func setClipboard(_ text: String, typing: Bool, _ done: @escaping (Result<ClipboardPath, CLIError>) -> Void) {
        let text = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard text.utf8.count <= HelperProtocol.clipboardLimit else {
            return done(.failure(.failure("the text is over \(HelperProtocol.clipboardLimit >> 20) MiB, too much for the clipboard")))
        }
        func typeInstead() {
            let none = "the guest has no clipboard"
            guard typing else { return done(.failure(.failure(none))) }
            guard text.utf8.count <= Owner.typeLimit else {
                return done(.failure(.failure("\(none), and the text is over \(Owner.typeLimit >> 10) KiB, too much to type")))
            }
            do { _ = try Input.text(text) } catch {
                return done(.failure(.failure("\(none), and the text cannot be typed: \(Owner.message(error).message)")))
            }
            guard let port = vnc?.port else { return done(.failure(.failure("\(none), and the VM's display is not ready"))) }
            DispatchQueue.global().async {
                let result = Result { _ = try Display.perform("type", ["text": text], port: port); return ClipboardPath.typed }
                    .mapError(Owner.message)
                DispatchQueue.main.async { done(result) }
            }
        }
        connectOnce { connection in
            guard let connection else { return typeInstead() }
            DispatchQueue.global().async {
                let result = Result<ClipboardPath, Error> { try HelperProtocol.storeClipboard(text, over: connection); return .helper }
                DispatchQueue.main.async {
                    switch result {
                    case .success(let path): done(.success(path))
                    case .failure(HelperProtocol.ClipboardFailure.unavailable): typeInstead()
                    case .failure(let error): done(.failure(Owner.message(error)))
                    }
                }
            }
        }
    }

    /// A `clipboard` request: `{"verb": "clipboard", "action": "get"}`, or `"set"` with `"text"`. A get answers with the text,
    /// a set with `typed` when the text was typed and nothing otherwise.
    func runClipboard(_ body: [String: Any], _ reply: Reply) {
        switch body["action"] as? String {
        case "get":
            getClipboard { result in
                switch result {
                case .success(let text): reply(ok(Data(text.utf8)))
                case .failure(let error): reply(failed(error.message))
                }
            }
        case "set":
            guard let text = body["text"] as? String else { return reply(failed("clipboard set needs text")) }
            setClipboard(text, typing: true) { result in
                switch result {
                case .success(.typed): reply(ok(Data("typed".utf8)))
                case .success(.helper): reply(ok())
                case .failure(let error): reply(failed(error.message))
                }
            }
        default:
            reply(failed("clipboard needs an action, get or set"))
        }
    }
}
