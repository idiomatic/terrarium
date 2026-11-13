import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

/// `record`: a video of a VM's display, read over its VNC server and encoded with `AVAssetWriter` (H.264), in the owner process.
/// Frames are appended only when the screen or an overlay changed, at most `fps` a second, stamped with the time they came, so
/// a still screen costs nothing and plays as a held frame. The pointer is drawn for guests that do not draw it into their
/// framebuffer (all but Windows), and `clicks` marks each press with a dot and a ring, and the release of a drag with a ring.
final class Recorder: @unchecked Sendable {
    struct Options {
        var url: URL
        var fps: Int
        var maxSeconds: Int
        /// The rectangle of guest pixels to keep, in the first frame's coordinates.
        var crop: CGRect?
        var clicks: Bool
        var drawPointer: Bool
    }

    /// How long a click's mark lasts; the radius its ring grows from and to, and its dot's at the start, in guest pixels at 1x.
    static let markDuration = 0.35
    static let ringRadius = (start: 6.0, end: 26.0)
    static let dotRadius = 9.0
    /// terrarium's diagram hues, brightened: amber for the left button, blue for the right, purple for the middle.
    static let markColors: [Int: (Double, Double, Double)] = [
        1: (0xe0 / 255.0, 0xa5 / 255.0, 0x26 / 255.0),
        4: (0x5b / 255.0, 0x8f / 255.0, 0xd6 / 255.0),
        2: (0x9b / 255.0, 0x74 / 255.0, 0xd1 / 255.0),
    ]

    /// A click's mark: a press has a dot and a ring, the release of a drag a ring alone.
    private struct Mark {
        let x: Int
        let y: Int
        let button: Int
        let press: Bool
        let start: Date
    }

    private let options: Options
    private let lock = NSLock()
    private var pointer: (x: Int, y: Int)?
    private var buttons = 0
    private var pressedAt: (x: Int, y: Int)?
    private var marks: [Mark] = []
    private var pointerMoved = false
    private var stopRequested = false
    private var summary = ""
    private let done = DispatchSemaphore(value: 0)
    /// Called once, on the recording's thread, when it ends by itself or is stopped, with what `stop` returns.
    private let ended: (Recorder, String) -> Void

    /// The file being written.
    var path: String { options.url.path }

    private init(_ options: Options, pointer: (x: Int, y: Int)?, ended: @escaping (Recorder, String) -> Void) {
        self.options = options
        self.pointer = pointer
        self.ended = ended
    }

    /// Starts recording the display on `port`; returns once the first frame is in, or throws why it could not start.
    /// `ended` is called on the recording's thread when it ends, by itself or by `stop`, with what `stop` returns.
    static func start(port: UInt16, _ options: Options, pointer: (x: Int, y: Int)?, ended: @escaping (Recorder, String) -> Void) throws -> Recorder {
        let recorder = Recorder(options, pointer: pointer, ended: ended)
        let started = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var failure: Error?
        Thread.detachNewThread {
            recorder.run(port: port) { error in
                failure = error
                started.signal()
            }
        }
        guard started.wait(timeout: .now() + 30) == .success else { throw CLIError.failure("the VM's display did not answer") }
        if let failure { throw failure }
        return recorder
    }

    /// Ends the recording, waits for the file to be written, and returns its path, duration, and frame count.
    func stop() -> String {
        lock.withLock { stopRequested = true }
        done.wait()
        done.signal()
        return summary
    }

    /// Where the pointer is and which buttons are down, as the owner sends them: a press starts a mark, and so does the
    /// release of a drag.
    func pointerEvent(x: Int, y: Int, buttons: Int) {
        lock.withLock {
            let pressed = buttons & 7, wasPressed = self.buttons & 7
            if options.clicks {
                if pressed != 0 && wasPressed == 0 {
                    marks.append(Mark(x: x, y: y, button: pressed, press: true, start: Date()))
                    pressedAt = (x, y)
                } else if pressed == 0 && wasPressed != 0, let from = pressedAt, from != (x, y) {
                    marks.append(Mark(x: x, y: y, button: wasPressed, press: false, start: Date()))
                }
            }
            if pointer.map({ $0 != (x, y) }) ?? true { pointerMoved = true }
            pointer = (x, y)
            self.buttons = buttons
        }
    }

    /// The recording's thread: connects, writes frames until stopped, the time is up, or the display goes away, then
    /// finishes the file. `started` is called once, with nil when the first frame is in or with why it failed.
    private func run(port: UInt16, started: @escaping (Error?) -> Void) {
        var startedCalled = false
        func start(_ error: Error?) {
            if !startedCalled { startedCalled = true; started(error) }
        }
        var writer: AVAssetWriter?
        var receiver: AVAssetWriterInput.PixelBufferReceiver?
        var outputSize = CGSize.zero
        var source = CGRect.zero
        let begin = Date()
        var lastAppend = -Double.infinity
        var lastTime = CMTime.zero
        var frames = 0
        var pending = false
        var reason = "stopped"
        let interval = 1 / Double(options.fps)
        do {
            let rfb = try RFB(port: port)
            try rfb.follow(interval: interval) { pixels, width, height, changed in
                if writer == nil {
                    // The first frame fixes the output's size: the crop, or the whole screen, rounded down to even sides.
                    do {
                        let full = CGRect(x: 0, y: 0, width: width, height: height)
                        if let crop = options.crop, !full.contains(crop) {
                            throw CLIError.usage("--crop \(Int(crop.minX)),\(Int(crop.minY)),\(Int(crop.width)),\(Int(crop.height)) is outside the \(width)x\(height) display")
                        }
                        source = options.crop ?? full
                        outputSize = CGSize(width: Int(source.width) & ~1, height: Int(source.height) & ~1)
                        (writer, receiver) = try Self.makeWriter(options.url, size: outputSize)
                        start(nil)
                    } catch {
                        start(error)
                        return false
                    }
                }
                let now = Date().timeIntervalSince(begin)
                if lock.withLock({ stopRequested }) { return false }
                if now >= Double(options.maxSeconds) { reason = "reached --max-seconds"; return false }
                let overlay = lock.withLock { () -> Bool in
                    // A mark that just expired needs one more frame without it, or its last, faded frame is held.
                    let before = marks.count
                    marks.removeAll { Date().timeIntervalSince($0.start) > Self.markDuration }
                    let busy = !marks.isEmpty || marks.count != before || (options.drawPointer && pointerMoved)
                    pointerMoved = false
                    return busy
                }
                pending = pending || changed || overlay || frames == 0
                guard pending, now - lastAppend >= interval * 0.9, let receiver, let pool = receiver.pixelBufferPool,
                      let buffer = try? pool.makeMutablePixelBuffer() else { return true }
                let time = CMTime(seconds: now, preferredTimescale: 600)
                guard time > lastTime || frames == 0 else { return true }
                buffer.withUnsafeBuffer { draw(into: $0, outputSize: outputSize, source: source, pixels: pixels, width: width, height: height) }
                // A frame the encoder is not ready for is dropped; the next tick sends the screen as it is then.
                if (try? receiver.appendImmediately(CVReadOnlyPixelBuffer(buffer), with: frames == 0 ? .zero : time)) == true {
                    frames += 1
                    lastTime = time
                    lastAppend = now
                    pending = false
                }
                return true
            }
            if !lock.withLock({ stopRequested }) && reason == "stopped" { reason = "the display went away" }
        } catch {
            if writer == nil { start(error) }
            reason = "the display went away"
        }
        if let writer, let receiver {
            let end = CMTime(seconds: Date().timeIntervalSince(begin), preferredTimescale: 600)
            receiver.finish()
            writer.endSession(atSourceTime: max(end, lastTime))
            let written = DispatchSemaphore(value: 0)
            writer.finishWriting { written.signal() }
            written.wait()
            if writer.status == .completed {
                summary = String(format: "%@: %.1f s, %d frame%@%@", options.url.path, CMTimeGetSeconds(max(end, lastTime)), frames,
                                 frames == 1 ? "" : "s", reason == "stopped" ? "" : " (\(reason))")
            } else {
                summary = "the recording failed: \(writer.error?.localizedDescription ?? "unknown error")"
            }
            ended(self, summary)
        }
        done.signal()
    }

    /// A writer of H.264 video of `size`, as a QuickTime movie or an MPEG-4 file by the path's extension.
    private static func makeWriter(_ url: URL, size: CGSize) throws -> (AVAssetWriter, AVAssetWriterInput.PixelBufferReceiver) {
        let type: AVFileType = url.pathExtension.lowercased() == "mov" ? .mov : .mp4
        let writer = try AVAssetWriter(outputURL: url, fileType: type)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        guard writer.canAdd(input) else { throw CLIError.failure("cannot record video of \(Int(size.width))x\(Int(size.height))") }
        let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: CVPixelBufferCreationAttributes(
            pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA), size: CVImageSize(width: Int(size.width), height: Int(size.height))))
        do { try writer.start() } catch { throw CLIError.failure("cannot write \(url.path): \(error.localizedDescription)") }
        writer.startSession(atSourceTime: .zero)
        return (writer, receiver)
    }

    /// Where `source` (guest pixels) goes in an output of `size`: scaled to fit, keeping its aspect ratio, centered.
    static func fit(_ source: CGSize, in size: CGSize) -> CGRect {
        let scale = min(size.width / source.width, size.height / source.height)
        let width = source.width * scale, height = source.height * scale
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    /// Draws the frame: the source rectangle of the guest's pixels, fitted into the output, then the click marks and the
    /// pointer over it.
    private func draw(into buffer: CVPixelBuffer, outputSize: CGSize, source: CGRect, pixels: UnsafeRawBufferPointer, width: Int, height: Int) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let space = CGColorSpaceCreateDeviceRGB()
        let order = CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: Int(outputSize.width), height: Int(outputSize.height), bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | order),
              let provider = CGDataProvider(dataInfo: nil, data: pixels.baseAddress!, size: pixels.count, releaseData: { _, _, _ in }),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | order),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return }
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: outputSize))
        // A display that changed size since the first frame keeps the crop where it fits, else shows whole.
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        let shown = full.contains(source) ? source : full
        let target = Self.fit(shown.size, in: outputSize)
        let scale = target.width / shown.width
        context.interpolationQuality = scale == 1 ? .none : .high
        if let part = image.cropping(to: shown) { context.draw(part, in: target) }
        // Guest coordinates (top left, y down) to the output's (bottom left, y up).
        func place(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: target.minX + (x - shown.minX) * scale, y: target.maxY - (y - shown.minY) * scale)
        }
        // A display of over 2000 pixels across is drawn at 2x, as a Retina guest's would be.
        let size = (width > 2000 ? 2.0 : 1.0) * scale
        let (marks, pointer) = lock.withLock { (self.marks, self.pointer) }
        context.clip(to: target)
        for mark in marks {
            // Eased out: quick at first, settling as it fades.
            let progress = min(1, Date().timeIntervalSince(mark.start) / Self.markDuration)
            let eased = 1 - (1 - progress) * (1 - progress)
            let alpha = 0.95 * (1 - progress)
            let (r, g, b) = Self.markColors[mark.button] ?? Self.markColors[1]!
            let color = CGColor(red: r, green: g, blue: b, alpha: alpha)
            // A dark edge under the color keeps the mark visible on a light screen; on a dark one the color shows by itself.
            let edge = CGColor(red: 0, green: 0, blue: 0, alpha: alpha * 0.55)
            let center = place(Double(mark.x), Double(mark.y))
            func circle(_ radius: Double) -> CGRect { CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2) }
            if mark.press {
                let dot = circle(Self.dotRadius * (1 - eased) * size)
                context.setFillColor(edge)
                context.fillEllipse(in: dot.insetBy(dx: -size, dy: -size))
                context.setFillColor(color)
                context.fillEllipse(in: dot)
            }
            let ring = circle((Self.ringRadius.start + (Self.ringRadius.end - Self.ringRadius.start) * eased) * size)
            context.setStrokeColor(edge)
            context.setLineWidth(5 * size)
            context.strokeEllipse(in: ring)
            context.setStrokeColor(color)
            context.setLineWidth(3 * size)
            context.strokeEllipse(in: ring)
        }
        if options.drawPointer, let pointer {
            // The classic arrow, its tip at the pointer, black with a white edge.
            let shape: [(Double, Double)] = [(0, 0), (0, 17), (4, 13), (7, 20), (10, 19), (7, 12), (12, 12)]
            let tip = place(Double(pointer.x), Double(pointer.y))
            context.beginPath()
            for (index, point) in shape.enumerated() {
                let p = CGPoint(x: tip.x + point.0 * size, y: tip.y - point.1 * size)
                if index == 0 { context.move(to: p) } else { context.addLine(to: p) }
            }
            context.closePath()
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.setLineWidth(1.5 * size)
            context.setLineJoin(.round)
            context.drawPath(using: .fillStroke)
        }
    }
}
