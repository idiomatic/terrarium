import Foundation
import TerrariumCore

/// Following the guest's display size with the window's shape.
extension RunWindow {
    /// The window always keeps the guest's aspect ratio, so no bars appear around the picture, and takes a new one once the
    /// size has held for ten seconds in the first two minutes after the VM starts (a booting guest passes through firmware
    /// modes: Windows sits at 1280x720 for about seven seconds after each reset), and for one second after that. It keeps
    /// its scale step.
    func guestSizeChanged(_ size: CGSize) {
        shapeWork?.cancel()
        guard size != lockedSize else { return }
        let hold: TimeInterval = Date().timeIntervalSince(owner.vmStartedAt) < 120 ? 10 : 1
        let shape = DispatchWorkItem { [self] in
            lockedSize = size
            lockAspect(to: size)
        }
        shapeWork = shape
        DispatchQueue.main.asyncAfter(deadline: .now() + hold, execute: shape)
    }
}
