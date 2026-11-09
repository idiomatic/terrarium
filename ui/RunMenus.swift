import AppKit
import Foundation
import TerrariumCore
import UniformTypeIdentifiers
import Virtualization

/// The window's menus and what they do.
extension RunWindow {
    func installMenus(app: NSApplication) {
        func entry(_ title: String, _ action: Selector, _ key: String = "", _ flags: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
            entry.keyEquivalentModifierMask = flags
            entry.target = target ?? self
            return entry
        }
        func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            items.forEach(submenu.addItem)
            item.submenu = submenu
            return item
        }

        let main = NSMenu()
        main.addItem(menu("Terrarium", [
            entry("About Terrarium", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: app),
            .separator(),
            entry("Hide Terrarium", #selector(NSApplication.hide(_:)), "h", target: app),
            entry("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option], target: app),
            entry("Show All", #selector(NSApplication.unhideAllApplications(_:)), target: app),
            .separator(),
            entry("Stop VM and Quit", #selector(quit), "q"),
        ]))

        let onStop = entry("Commit When VM Stops…", #selector(toggleSaveOnStop))
        saveOnStopItem = onStop
        onStop.state = saveOnStop != nil ? .on : .off
        main.addItem(menu("File", [
            entry("Commit…", #selector(commitNow), "s"),
            onStop,
            .separator(),
            entry("Screenshot…", #selector(screenshot), "s", [.command, .shift]),
            .separator(),
            entry("Reveal VM Folder", #selector(revealFolder), "r", [.command, .shift]),
            entry("Copy VM ID", #selector(copyID)),
            .separator(),
            entry("Stop VM and Close Window", #selector(quit), "w"),
        ]))

        let share = entry("Share Clipboard", #selector(toggleShareClipboard))
        share.state = sharingClipboard ? .on : .off
        shareClipboardItem = share
        main.addItem(menu("Edit", [
            entry("Paste to Guest", #selector(pasteToGuest), "v"),
            entry("Copy from Guest", #selector(copyFromGuest), "c"),
            .separator(),
            share,
        ]))

        let pause = entry("Pause", #selector(togglePause), "p", [.command, .option])
        pauseItem = pause
        // Each item names its effect, then its chord, since a chord does different things in different guests. Only the
        // guest's own OS is listed; the chords are the ones the host keeps, or that no host key reaches the guest as.
        func keyItem(_ title: String, _ chord: String) -> NSMenuItem {
            let item = entry(title, #selector(sendKey(_:)))
            item.representedObject = chord
            return item
        }
        var keyItems = [keyItem("Escape", "esc"), .separator()]
        switch owner.guestName {
        case "windows":
            keyItems += [
                keyItem("Security Screen (Ctrl+Alt+Delete)", "ctrl+alt+delete"),
                keyItem("Start Menu (Windows Key)", "win"),
                keyItem("Run (Win+R)", "win+r"),
                keyItem("Show Desktop (Win+D)", "win+d"),
                keyItem("Task Manager (Ctrl+Shift+Esc)", "ctrl+shift+esc"),
                keyItem("Switch Window (Alt+Tab)", "alt+tab"),
                keyItem("Close Window (Alt+F4)", "alt+f4"),
                keyItem("Context Menu (Shift+F10)", "shift+f10"),
            ]
        case "macos":
            keyItems += [
                keyItem("Spotlight (Cmd+Space)", "win+space"),
                keyItem("Switch App (Cmd+Tab)", "win+tab"),
                keyItem("Quit App (Cmd+Q)", "win+q"),
                keyItem("Force Quit (Cmd+Option+Esc)", "win+alt+esc"),
                keyItem("Lock Screen (Ctrl+Cmd+Q)", "ctrl+win+q"),
                keyItem("Mission Control (Ctrl+Up)", "ctrl+up"),
            ]
        default:
            keyItems += [
                keyItem("Log Out (Ctrl+Alt+Delete)", "ctrl+alt+delete"),
                menu("Switch Console", (1...6).map { keyItem("Console \($0) (Ctrl+Alt+F\($0))", "ctrl+alt+f\($0)") }),
                menu("Desktop", [
                    keyItem("Activities (Super)", "win"),
                    keyItem("Show All Apps (Super+A)", "win+a"),
                    keyItem("Run Command (Alt+F2)", "alt+f2"),
                    keyItem("Terminal (Ctrl+Alt+T)", "ctrl+alt+t"),
                    keyItem("Switch Window (Alt+Tab)", "alt+tab"),
                    keyItem("Close Window (Alt+F4)", "alt+f4"),
                    keyItem("Screen Capture (Shift+Ctrl+Alt+R)", "shift+ctrl+alt+r"),
                ]),
            ]
        }
        main.addItem(menu("VM", [
            pause,
            .separator(),
            menu("Send Key", keyItems),
            entry("Capture System Keys", #selector(toggleSystemKeys)),
        ]))

        // The guest keeps its size, so the window is a scaled view of it, in steps.
        let scaleItems = RunWindow.scales.map { step -> NSMenuItem in
            let item = entry("\(Int((step * 100).rounded()))%", #selector(setScale(_:)))
            item.representedObject = Double(step)
            return item
        }
        // Command-= is Zoom In without Shift too; the same item, hidden, carries that binding.
        let zoomInUnshifted = entry("Zoom In", #selector(zoomIn), "=")
        zoomInUnshifted.isHidden = true
        zoomInUnshifted.allowsKeyEquivalentWhenHidden = true
        main.addItem(menu("View", [
            entry("Actual Size", #selector(actualSize), "0"),
            entry("Zoom In", #selector(zoomIn), "+"),
            zoomInUnshifted,
            entry("Zoom Out", #selector(zoomOut), "-"),
            .separator(),
            menu("Scale", scaleItems),
            .separator(),
            entry("Match Guest to Window", #selector(matchGuestToWindow), "f", [.command, .option]),
        ]))
        let windowMenu = menu("Window", [
            entry("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m", target: nil),
            .separator(),
            entry("Console Log", #selector(showConsoleLog), "l", [.command, .option]),
        ])
        main.addItem(windowMenu)
        app.mainMenu = main
        app.windowsMenu = windowMenu.submenu
    }

    /// Stops the VM by closing the window, which asks first when the VM has uncommitted changes.
    @objc private func quit() {
        if let window { window.performClose(nil) } else { owner.stopAndExit(reply: nil) }
    }

    /// Asks what to do with changes made since the last commit, as a sheet so the VM keeps running behind it.
    func confirmStop() {
        guard let window, window.attachedSheet == nil else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Stop the VM?"
        alert.informativeText = installing
            ? "The install has not been committed. Stopping now discards it."
            : "The VM has changes that were not committed. Stopping discards them."
        alert.addButton(withTitle: "Commit…")
        let discard = alert.addButton(withTitle: "Stop Without Committing")
        discard.keyEquivalent = "d"
        discard.keyEquivalentModifierMask = .command
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [self] response in
            switch response {
            case .alertFirstButtonReturn:
                // A second sheet cannot start until the first has finished closing.
                DispatchQueue.main.async { [self] in commitThenStop() }
            case .alertSecondButtonReturn:
                owner.stopAndExit(reply: nil)
            default:
                break
            }
        }
    }

    private func commitThenStop() {
        chooseName(message: "The VM stops when the commit is done.") { [self] prefix in
            owner.saveOverlay(to: prefix) { [self] result in
                switch result {
                case .success(let url):
                    note("\(kind) saved to \(url.path)")
                    owner.stopAndExit(reply: nil)
                case .failure(let error):
                    warn("Could not commit", error)
                }
            }
        }
    }

    @objc private func copyID() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(owner.id, forType: .string)
    }

    @objc private func revealFolder() {
        let marker = owner.directory.appendingPathComponent("info.json")
        NSWorkspace.shared.activateFileViewerSelecting([FileManager.default.fileExists(atPath: marker.path) ? marker : owner.directory])
    }

    @objc private func toggleSystemKeys(_ sender: NSMenuItem) {
        guard let view else { return }
        view.capturesSystemKeys.toggle()
        sender.state = view.capturesSystemKeys ? .on : .off
        showShortcuts(!view.capturesSystemKeys)
    }

    /// The guest gets every key while Capture System Keys is on, so the menus' key equivalents would not work: they are cleared
    /// from the menus then, and put back when it is turned off.
    private func showShortcuts(_ visible: Bool) {
        func walk(_ menu: NSMenu?) {
            for item in menu?.items ?? [] {
                let id = ObjectIdentifier(item)
                if visible, let saved = hiddenShortcuts.removeValue(forKey: id) {
                    item.keyEquivalent = saved.key
                    item.keyEquivalentModifierMask = saved.flags
                } else if !visible, !item.keyEquivalent.isEmpty {
                    hiddenShortcuts[id] = (item.keyEquivalent, item.keyEquivalentModifierMask)
                    item.keyEquivalent = ""
                }
                walk(item.submenu)
            }
        }
        walk(NSApp.mainMenu)
    }

    @objc func togglePause() { owner.togglePause() }

    @objc func sendKey(_ sender: NSMenuItem) {
        if let chord = sender.representedObject as? String { owner.sendKey(chord) }
    }

    @objc func screenshot() {
        owner.screenshot { [self] png in
            switch png {
            case .success(let data):
                guard let window else { return }
                let panel = NSSavePanel()
                panel.title = "Screenshot"
                panel.allowedContentTypes = [.png]
                panel.nameFieldStringValue = "terrarium-\(id).png"
                panel.canCreateDirectories = true
                panel.beginSheetModal(for: window) { [self] response in
                    guard response == .OK, let url = panel.url else { return }
                    do { try data.write(to: url) } catch { warn("Could not save the screenshot", error) }
                }
            case .failure(let error):
                warn("Could not take the screenshot", error)
            }
        }
    }

    @objc func showConsoleLog() {
        if consoleLog == nil { consoleLog = ConsoleLog(file: owner.consoleLog, title: "Terrarium \(id) console") }
        consoleLog?.show()
    }

    /// Asks where to save the commit, as a sheet so the VM keeps running while the panel is open.
    private func chooseName(message: String, then done: @escaping (URL) -> Void) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.title = "Commit"
        panel.message = "\(message) It is saved as \(owner.overlayTarget(URL(fileURLWithPath: "NAME")).lastPathComponent)."
        panel.nameFieldStringValue = owner.imageBaseName
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, var url = panel.url else { return }
            if url.pathExtension == self.kind { url.deletePathExtension() }
            done(url)
        }
    }

    @objc private func commitNow() {
        let warning = installing ? "The installer powers the VM off when it finishes, so “Commit When VM Stops…” is safer; this copies the disk as it is now." : "Copies the disk as the guest has flushed it."
        chooseName(message: warning) { [self] prefix in
            owner.saveOverlay(to: prefix) { [self] result in
                switch result {
                case .success(let url):
                    note("\(kind) saved to \(url.path)")
                case .failure(let error):
                    warn("Could not commit", error)
                }
            }
        }
    }

    @objc private func toggleSaveOnStop() {
        if saveOnStop != nil {
            saveOnStop = nil
            saveOnStopItem?.state = .off
            return
        }
        let message = installing ? "The install is committed when the installer shuts the VM down." : "Committed when the VM stops."
        chooseName(message: message) { [self] prefix in
            do {
                try owner.checkSaveTarget(prefix)
                saveOnStop = prefix
            } catch {
                warn("Could not commit", error)
            }
        }
    }
}
