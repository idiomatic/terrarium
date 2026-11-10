import Foundation
import Virtualization

extension Owner {
    /// How long a flush waits for the helper to answer, and how long the guest has to write its disk.
    private static let flushWait: TimeInterval = 5
    private static let flushTimeout: TimeInterval = 30

    /// What makes the guest write what it holds in memory to its disk: `sync`, or on Windows flushing the system volume.
    private var flushArgv: [String] {
        switch guestOS {
        case .windows: ["powershell", "-NoProfile", "-NonInteractive", "-Command", "Write-VolumeCache -DriveLetter C"]
        default: ["sync"]
        }
    }

    /// Asks the guest to write its disk out, so that a save made next holds what the guest has done: a stop powers the VM off
    /// without asking the guest, and a layer saved then would lack whatever the guest still had in memory. Best effort: a guest
    /// whose helper does not answer within a few seconds (a console, an installer, a boot in progress) is saved as it is,
    /// with a note. Call it on the main queue before the VM is stopping or paused; `done` runs on the main queue.
    func flushGuest(then done: @escaping () -> Void) {
        guard helperExpected, !stopping, vm.state == .running else { return done() }
        connectHelper(until: Date().addingTimeInterval(Owner.flushWait)) { [self] connection in
            guard let connection else {
                note("terrarium: the guest's helper did not answer, so its disk is saved as the guest left it")
                return done()
            }
            DispatchQueue.global().async { [self] in
                let (status, output) = Owner.collect(argv: flushArgv, timeout: Owner.flushTimeout,
                                                     timedOut: "terrarium: the guest did not write its disk within \(Int(Owner.flushTimeout)) s\n", over: connection)
                DispatchQueue.main.async {
                    if status != 0 {
                        let why = output.trimmingCharacters(in: .whitespacesAndNewlines)
                        note("terrarium: the guest could not write its disk (exit \(status)\(why.isEmpty ? "" : ": " + why)), so it is saved as the guest left it")
                    }
                    done()
                }
            }
        }
    }
}
