import AppKit
import Foundation
import TerrariumCore
import Virtualization

/// The window's scale: device pixels per guest pixel, in steps.
extension RunWindow {
    /// The steps the window snaps to, as device pixels per guest pixel: 100% shows each guest pixel as one pixel of the screen.
    /// The whole ratios are crisp (25% and 50%, 200% and 300%); the others make finer steps.
    static let scales: [CGFloat] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3]

    /// The window's content size, in points, for the guest at a scale: a device pixel is `1 / backingScaleFactor` points.
    private func contentSize(scale: CGFloat) -> NSSize {
        let backing = window?.backingScaleFactor ?? 1
        return NSSize(width: (guestSize.width * scale / backing).rounded(), height: (guestSize.height * scale / backing).rounded())
    }

    /// The step nearest to a content width in points.
    private func nearestScale(forWidth width: CGFloat) -> CGFloat {
        let actual = width * (window?.backingScaleFactor ?? 1) / guestSize.width
        return RunWindow.scales.min { abs($0 - actual) < abs($1 - actual) } ?? 1
    }

    /// Sets the window to a scale, and keeps the scale it ends up with (a window larger than the screen is shrunk to fit).
    func applyScale(_ target: CGFloat) {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        window.setContentSize(contentSize(scale: target))
        scale = nearestScale(forWidth: window.contentRect(forFrameRect: window.frame).width)
    }

    /// Whether a window at this scale fits the screen it is on; a larger one would be shrunk to the largest step that does.
    func scaleFits(_ target: CGFloat) -> Bool {
        guard let window, let visible = window.screen?.visibleFrame, !window.styleMask.contains(.fullScreen) else { return false }
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize(scale: target))).size
        return frame.width <= visible.width && frame.height <= visible.height
    }

    /// The largest step at or below `target` that fits the screen, or the smallest step when none does; `target` itself while
    /// the window has no screen (or is full screen) to fit.
    func fittingScale(_ target: CGFloat) -> CGFloat {
        guard let window, window.screen != nil, !window.styleMask.contains(.fullScreen) else { return target }
        return RunWindow.scales.last { $0 <= target + 0.001 && scaleFits($0) } ?? RunWindow.scales[0]
    }

    @objc func setScale(_ item: NSMenuItem) {
        if let target = item.representedObject as? Double { applyScale(CGFloat(target)) }
    }

    @objc func actualSize() { applyScale(1) }

    /// The next step up or down that fits the screen, if there is one.
    func nextScale(_ direction: Int) -> CGFloat? {
        guard let index = RunWindow.scales.firstIndex(where: { abs($0 - scale) < 0.001 }) else { return nil }
        var i = index + direction
        while RunWindow.scales.indices.contains(i) {
            if scaleFits(RunWindow.scales[i]) { return RunWindow.scales[i] }
            i += direction
        }
        return nil
    }

    @objc func zoomIn() { if let next = nextScale(1) { applyScale(next) } }
    @objc func zoomOut() { if let next = nextScale(-1) { applyScale(next) } }

    /// Resizing the window snaps to the nearest scale step.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === window else { return frameSize }
        let content = sender.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize)).size
        scale = nearestScale(forWidth: content.width)
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize(scale: scale))).size
    }

    /// On a screen with another pixel density the scale is kept, so the window's size in points changes.
    func windowDidChangeBackingProperties(_ notification: Notification) {
        guard let window, window.backingScaleFactor != lastBacking else { return }
        lastBacking = window.backingScaleFactor
        applyScale(scale)
    }

    /// Asks the guest, once, for a display of the window's size in pixels (the view's points times the screen's scale), so the
    /// picture is sharp at the window's size. A guest that follows then reports that size, and the window keeps its size, so its
    /// scale becomes whatever the new size makes it: 100% (pixel-exact). A guest that ignores the request changes nothing.
    @objc func matchGuestToWindow() {
        guard let window, let view, let display = vm.graphicsDevices.first?.displays.first else { return }
        let target = CGSize(width: (view.bounds.width * window.backingScaleFactor).rounded(),
                            height: (view.bounds.height * window.backingScaleFactor).rounded())
        do {
            try display.reconfigure(sizeInPixels: target)
        } catch {
            return warn("Could not match the guest to the window", error)
        }
        matchTarget = target
        matchWork?.cancel()
        let expire = DispatchWorkItem { [self] in matchTarget = nil }
        matchWork = expire
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: expire)
    }

    /// Follows a new guest size: the aspect ratio is locked to it from then on, and the window keeps its scale step, unless
    /// the guest has just arrived at the size that Match Guest to Window asked for, when the window keeps its size.
    func lockAspect(to size: CGSize) {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        if let target = matchTarget, abs(size.width - target.width) <= 2, abs(size.height - target.height) <= 2 {
            matchTarget = nil
            guestSize = size
            window.contentAspectRatio = size
            scale = nearestScale(forWidth: window.contentRect(forFrameRect: window.frame).width)
            return
        }
        let keep = scale
        guestSize = size
        window.contentAspectRatio = size
        // A guest that grows keeps the window's scale only while the window still fits the screen.
        applyScale(fittingScale(keep))
    }
}
