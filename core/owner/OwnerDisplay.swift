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

    /// `record`: starts a recording of the display (`path`, `fps`, `maxSeconds`, `clicks`, and `crop` as X, Y, W, H), or ends
    /// the one running (`stop`). A start answers once the first frame is in; a stop once the file is written. A recording
    /// also ends at its time limit, when the display goes away (a Windows reset replaces it), and when the VM stops.
    func runRecord(_ body: [String: Any], _ reply: Reply) {
        if body["stop"] as? Bool == true {
            guard let recording else { return reply(failed("the VM is not recording")) }
            self.recording = nil
            Display.setRecorder(nil)
            DispatchQueue.global().async { reply(ok(Data(recording.stop().utf8))) }
            return
        }
        if let recording { return reply(failed("the VM is already recording (\(recording.path)): end it with record --stop")) }
        guard !recordingStarts else { return reply(failed("the VM is already starting a recording")) }
        guard let port = vnc?.port else { return reply(failed("the VM's display is not ready")) }
        guard let path = body["path"] as? String, let fps = body["fps"] as? Int, let maxSeconds = body["maxSeconds"] as? Int else {
            return reply(failed("record needs a path"))
        }
        let crop = (body["crop"] as? [Int]).map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
        let options = Recorder.Options(url: URL(fileURLWithPath: path), fps: fps, maxSeconds: maxSeconds, crop: crop,
                                       clicks: body["clicks"] as? Bool == true, drawPointer: guestOS != .windows)
        // Taken now, so a second start meanwhile is refused; the recording itself starts off the main queue, which the VNC
        // server shares.
        recordingStarts = true
        DispatchQueue.global().async { [self] in
            do {
                let started = try Recorder.start(port: port, options, pointer: Display.pointer) { ended, summary in
                    DispatchQueue.main.async { [self] in
                        guard recording === ended else { return }
                        recording = nil
                        Display.setRecorder(nil)
                        note("terrarium: recorded \(summary)")
                    }
                }
                DispatchQueue.main.async { [self] in
                    recordingStarts = false
                    recording = started
                    Display.setRecorder(started)
                    reply(ok(Data("recording to \(path)".utf8)))
                }
            } catch {
                DispatchQueue.main.async { [self] in recordingStarts = false }
                reply(failed((error as? CLIError)?.message ?? "\(error)"))
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
