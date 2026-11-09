import ObjectiveC
import Virtualization

/// Private Virtualization API that Windows needs: its boot manager draws nothing, and the guest crashes, without the
/// performance monitoring unit emulated. The selector is checked first, so a macOS without it only loses that.
enum PrivatePlatform {
    @discardableResult
    static func enablePerformanceMonitoring(_ platform: VZGenericPlatformConfiguration) -> Bool {
        let selector = NSSelectorFromString("_setPerformanceMonitoringUnitEmulationEnabled:")
        guard let method = class_getInstanceMethod(type(of: platform), selector) else { return false }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(method_getImplementation(method), to: Setter.self)(platform, selector, true)
        return true
    }
}
