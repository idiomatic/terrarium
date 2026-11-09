import AppKit
import Foundation
import TerrariumCore

/// A window onto the VM's console log, refreshed while it is open.
final class ConsoleLog: NSObject, NSWindowDelegate {
    private let file: URL
    private let window: NSWindow
    private let text = NSTextView()
    private var timer: Timer?

    init(file: URL, title: String) {
        self.file = file
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 760, height: 420))
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        text.isEditable = false
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.autoresizingMask = [.width]
        text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text
        window = NSWindow(contentRect: scroll.frame, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        window.contentView = scroll
        window.isReleasedWhenClosed = false
        super.init()
        window.delegate = self
    }

    func show() {
        refresh()
        window.makeKeyAndOrderFront(nil)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    /// The last 256 KiB, scrolled to the end unless the reader has scrolled up.
    private func refresh() {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 262_144 ? size - 262_144 : 0)
        let content = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        guard content != text.string else { return }
        let bottom = text.enclosingScrollView.map { $0.contentView.bounds.maxY >= text.frame.maxY - 20 } ?? true
        text.string = content
        if bottom { text.scrollToEndOfDocument(nil) }
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }
}
