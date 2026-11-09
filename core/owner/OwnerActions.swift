import Foundation
import Virtualization

/// What a front-end asks of an owner and reads from it.
extension Owner {
    /// The VM's state: `starting`, `running`, `paused`, `installing N%`, and so on.
    public var state: String { info.state }

    /// The stored image's name, as `images` and `ps` show it.
    public var imageName: String { Store.displayName(info.image, among: (try? Store.list()) ?? []) }

    /// The guest's OS: `windows`, `macos`, or `linux`.
    public var guestName: String { guestOS.rawValue }

    /// The stored image's name without its hash.
    public var imageBaseName: String { Store.baseName(of: info.image) }

    /// Whether an install is running (its result is an installed guest not yet committed).
    public var installing: Bool { savesInstalledOverlay && info.recipe?.hasPrefix("install:") == true }

    /// Whether the guest has a serial console to show (macOS has none).
    public var hasConsole: Bool { plan.kind != .macos }

    /// The console log, which the guest's serial port writes.
    public var consoleLog: URL { directory.appendingPathComponent("console.log") }

    /// The port of the VM's display, once there is one.
    public var displayPort: UInt16? { vnc?.port }

    public func togglePause() {
        if vm.canResume {
            vm.resume { [self] result in
                if case .success = result { info.state = "running"; try? Runtime.write(info) }
            }
        } else if vm.canPause {
            vm.pause { [self] result in
                if case .success = result { info.state = "paused"; try? Runtime.write(info) }
            }
        }
    }

    /// Presses a key or chord (`ctrl+alt+delete`) in the guest.
    public func sendKey(_ chord: String) {
        guard let port = vnc?.port else { return }
        DispatchQueue.global().async { _ = try? Display.perform("key", ["chord": chord], port: port) }
    }

    /// A PNG of the guest's display, delivered on the main queue.
    public func screenshot(_ done: @escaping (Result<Data, Error>) -> Void) {
        guard let port = vnc?.port else { return done(.failure(CLIError.failure("the VM's display is not ready"))) }
        DispatchQueue.global().async {
            let png = Result { try Display.perform("shot", [:], port: port) }
            DispatchQueue.main.async { done(png) }
        }
    }
}
