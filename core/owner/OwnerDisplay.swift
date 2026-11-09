import Foundation

/// Following the guest's display size, which `info.display` reports and a front-end's window can track.
extension Owner {
    /// Follows the guest's display size, which the guest can change by itself (Windows does when its display driver loads, a
    /// minute in; GNOME does when a mode is chosen in its Settings) without Virtualization's display object or its observer
    /// saying so. The VNC server announces it, so one connection is held open and each notice is acted on as it comes.
    /// A thread reconnects when the connection ends: a Windows reset replaces the VNC server.
    func trackGuestSize() {
        guard !sizeWatching else { return }
        sizeWatching = true
        Thread.detachNewThread { [self] in
            while !DispatchQueue.main.sync(execute: { stopping }) {
                if let port = DispatchQueue.main.sync(execute: { vnc?.port }), let rfb = try? RFB(port: port) {
                    // A reset replaces the VNC server; the old connection may stay open, so its port is checked too.
                    let current = { DispatchQueue.main.sync { !self.stopping && self.vnc?.port == port } }
                    try? rfb.watchSize(while: current) { size in DispatchQueue.main.async { self.guestSizeChanged(size) } }
                }
                Thread.sleep(forTimeInterval: 2)
            }
        }
    }

    /// A new size is shown in `info.display` once it has held for a second; the front-end hears of it at once.
    private func guestSizeChanged(_ size: CGSize) {
        reportWork?.cancel()
        let text = "\(Int(size.width))x\(Int(size.height))"
        if info.display != text {
            let report = DispatchWorkItem { [self] in
                info.display = text
                try? Runtime.write(info)
            }
            reportWork = report
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: report)
        }
        ui?.guestSizeChanged(size)
    }
}
