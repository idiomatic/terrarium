import AppKit
import Foundation
import TerrariumCore

/// Moving text between the host's pasteboard and the guest's clipboard: on request, and with Share Clipboard on, when the
/// window gains or loses focus.
extension RunWindow {
    static let shareClipboardKey = "shareClipboard"

    /// Sends the host's pasteboard text to the guest, typing it if the guest has no clipboard.
    @objc func pasteToGuest() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            return warn("Could not paste to the guest", CLIError.failure("The clipboard has no text."))
        }
        owner.setClipboard(text, typing: true) { [self] result in
            switch result {
            case .success(.helper): remember(text)
            case .success(.typed): note("the guest has no clipboard; typed the text instead")
            case .failure(let error): warn("Could not paste to the guest", error)
            }
        }
    }

    /// Puts the guest's clipboard text on the host's pasteboard.
    @objc func copyFromGuest() {
        owner.getClipboard { [self] result in
            switch result {
            case .success(let text): take(text)
            case .failure(let error): warn("Could not copy from the guest", error)
            }
        }
    }

    @objc func toggleShareClipboard(_ sender: NSMenuItem) {
        sharingClipboard.toggle()
        sender.state = sharingClipboard ? .on : .off
        UserDefaults.standard.set(sharingClipboard, forKey: RunWindow.shareClipboardKey)
        // Whatever is on the pasteboard now is not news when sharing starts.
        syncedChange = NSPasteboard.general.changeCount
    }

    /// Records that the host's pasteboard and the guest's clipboard hold `text`.
    private func remember(_ text: String) {
        syncedText = text
        syncedChange = NSPasteboard.general.changeCount
    }

    private func take(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        remember(text)
    }

    /// The window gained focus: the host's text goes to the guest if it changed. Failures go to the console log.
    func windowDidBecomeKey(_ notification: Notification) {
        guard sharingClipboard, vm.state == .running else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != syncedChange, let text = pasteboard.string(forType: .string), text != syncedText else { return }
        let change = pasteboard.changeCount
        owner.setClipboard(text, typing: false) { [self] result in
            switch result {
            case .success: syncedText = text; syncedChange = change
            case .failure(let error): note("terrarium: clipboard not shared with the guest: \(error.message)")
            }
        }
    }

    /// The window lost focus: the guest's text goes to the host's pasteboard if it differs.
    func windowDidResignKey(_ notification: Notification) {
        guard sharingClipboard, vm.state == .running else { return }
        owner.getClipboard { [self] result in
            switch result {
            case .success(let text): if text != syncedText { take(text) }
            case .failure(let error): note("terrarium: clipboard not shared with the host: \(error.message)")
            }
        }
    }
}
