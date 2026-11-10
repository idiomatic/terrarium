import AppKit
import Foundation
import TerrariumCore
import Virtualization

/// The window `run` shows; its menus are in `RunMenus.swift`, its scale in `RunScale.swift`, and its size tracking in `RunSize.swift`.
final class RunWindow: NSObject, OwnerUI, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let owner: Owner
    var window: NSWindow?
    var view: VZVirtualMachineView?
    var saveOnStopItem: NSMenuItem?
    var pauseItem: NSMenuItem?
    var consoleLog: ConsoleLog?
    var keyMonitor: Any?
    /// Whether Share Clipboard is on, and the text and pasteboard change count of the last sync, to send or fetch only changes.
    var sharingClipboard = UserDefaults.standard.bool(forKey: RunWindow.shareClipboardKey)
    var shareClipboardItem: NSMenuItem?
    var syncedText: String?
    var syncedChange = -1
    /// The key equivalents cleared from the menus while Capture System Keys is on, by item.
    var hiddenShortcuts: [ObjectIdentifier: (key: String, flags: NSEvent.ModifierFlags)] = [:]
    var shapeWork: DispatchWorkItem?
    var lockedSize = CGSize(width: 1280, height: 800)
    /// The size, in pixels, that Match Guest to Window asked for: when the guest arrives at it, the window keeps its size.
    var matchTarget: CGSize?
    var matchWork: DispatchWorkItem?
    /// The guest display size (pixels) that the window's scale applies to.
    var guestSize = CGSize(width: 1280, height: 800)
    /// The window's scale: device (host) pixels per guest pixel, one of `RunWindow.scales`.
    var scale: CGFloat = 1
    /// The screen's pixel density the scale was last applied at, so a move to another screen keeps the scale.
    var lastBacking: CGFloat = 0

    init(_ owner: Owner) { self.owner = owner }

    // What the window reads of its owner.
    var id: String { owner.id }
    var vm: VZVirtualMachine { owner.vm }
    var stopping: Bool { owner.stopping }
    var committing: Bool { owner.committing }
    var installing: Bool { owner.installing }
    var changedSinceCommit: Bool { owner.changedSinceCommit }
    var saveOnStop: URL? {
        get { owner.saveOnStop }
        set { owner.saveOnStop = newValue }
    }
    /// What a commit saves.
    var kind: String { "layer" }

    func runLoop() -> Never {
        NSApplication.shared.run()
        exit(0)
    }

    func stateChanged() {
        refreshTitle()
        saveOnStopItem?.state = saveOnStop == nil ? .off : .on
    }

    func vmReplaced() { view?.virtualMachine = vm }

    func show() {
        let app = NSApplication.shared
        // A bare executable has no bundle name, so the menu bar would show the file name.
        ProcessInfo.processInfo.processName = "Terrarium"
        app.setActivationPolicy(.regular)

        installMenus(app: app)
        app.delegate = self

        let view = VZVirtualMachineView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        view.virtualMachine = vm
        // Off: the host keeps its shortcuts (Cmd-Tab, screenshots); "Capture System Keys" turns it on.
        view.capturesSystemKeys = false
        view.automaticallyReconfiguresDisplay = false   // resizing the window changes the scale, not the guest
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.contentView = view
        // The window always keeps the guest's aspect ratio. The guest starts at the size it was configured with, and
        // `trackGuestSize` follows it from there.
        window.contentAspectRatio = view.frame.size
        // The starting 1280x800-point window holds a 1280x800 guest at the screen's pixel density: 200% on a Retina screen.
        lastBacking = window.backingScaleFactor
        scale = RunWindow.scales.min { abs($0 - lastBacking) < abs($1 - lastBacking) } ?? 1
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        // A screen too small for the starting window gets the largest step that fits.
        applyScale(fittingScale(scale))
        app.activate(ignoringOtherApps: true)
        self.window = window
        self.view = view
        // The VM view takes every key equivalent for the guest, so the menus would never see them: offer Command shortcuts to
        // the menus first, unless Capture System Keys gives the guest everything.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let view = self.view, !view.capturesSystemKeys, event.window === self.window,
                  event.modifierFlags.contains(.command), NSApp.mainMenu?.performKeyEquivalent(with: event) == true else { return event }
            return nil
        }
        refreshTitle()
    }

    /// The title carries the VM's state, so a finished install shows without watching the screen.
    func refreshTitle() {
        var title = "Terrarium \(id) — \(owner.imageName) — \(owner.transient ?? owner.state)"
        if saveOnStop != nil { title += " · commit when stopped" }
        window?.title = title
    }

    func warn(_ message: String, _ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = (error as? CLIError)?.message ?? error.localizedDescription
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }


    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(togglePause):
            item.title = vm.canResume ? "Resume" : "Pause"
            return vm.canPause || vm.canResume
        case #selector(setScale(_:)):
            let step = (item.representedObject as? Double) ?? 0
            item.state = abs(Double(scale) - step) < 0.001 ? .on : .off
            return scaleFits(CGFloat(step))
        case #selector(actualSize):
            return scaleFits(1)
        case #selector(zoomIn):
            return nextScale(1) != nil
        case #selector(zoomOut):
            return nextScale(-1) != nil
        case #selector(screenshot), #selector(sendKey(_:)):
            return owner.displayPort != nil
        case #selector(showConsoleLog):
            return owner.hasConsole
        case #selector(pasteToGuest), #selector(copyFromGuest):
            return vm.state == .running
        default:
            return true
        }
    }

    /// Quitting from the Dock, the app switcher, or a logout goes the same way as closing the window, so a scheduled commit is
    /// saved and uncommitted changes are asked about. AppKit's own termination is always cancelled: the owner exits by itself
    /// once the VM has stopped, and `.terminateLater` would hold the run loop in a mode where the VM's stop never completes.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        DispatchQueue.main.async { [self] in
            if !stopping, window != nil, saveOnStop == nil, !committing, changedSinceCommit {
                confirmStop()
            } else {
                owner.stopAndExit(reply: nil)
            }
        }
        return .terminateCancel
    }

    /// Closing the window stops the VM, so a VM with changes that were not committed asks first.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === window, !stopping, saveOnStop == nil, changedSinceCommit else { return true }
        confirmStop()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === window { owner.stopAndExit(reply: nil) }
    }
}

/// The front-end `run` uses: the owner's window, menus, and scale.
public func makeRunWindow(_ owner: Owner) -> OwnerUI { RunWindow(owner) }
