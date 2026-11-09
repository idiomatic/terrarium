import Foundation
import ObjectiveC
import Virtualization

/// The only use of private Virtualization API: `_VZVNCServer`, bound to loopback without security,
/// which gives `terrarium` a framebuffer to read and an input path. Every selector is checked first.
final class PrivateVNC {
    private let server: NSObject

    /// Starts the server for a running VM, or returns nil if this macOS does not have it.
    init?(_ vm: VZVirtualMachine) {
        guard let serverClass = NSClassFromString("_VZVNCServer") as? NSObject.Type,
              let securityClass = NSClassFromString("_VZVNCNoSecuritySecurityConfiguration") as? NSObject.Type else { return nil }
        let initSelector = NSSelectorFromString("initWithPort:queue:securityConfiguration:")
        let startSelector = NSSelectorFromString("start")
        // The keys used below through key-value coding are checked too: a missing one would raise, not return nil.
        guard serverClass.instancesRespond(to: initSelector), serverClass.instancesRespond(to: startSelector),
              serverClass.instancesRespond(to: NSSelectorFromString("setVirtualMachine:")),
              serverClass.instancesRespond(to: NSSelectorFromString("port")),
              let raw = serverClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() else { return nil }
        typealias Init = @convention(c) (AnyObject, Selector, UInt16, DispatchQueue, AnyObject) -> AnyObject
        let make = unsafeBitCast(class_getMethodImplementation(serverClass, initSelector), to: Init.self)
        server = make(raw, initSelector, 0, vm.queue, securityClass.init()) as! NSObject
        server.setValue(vm, forKey: "virtualMachine")
        server.perform(startSelector)
    }

    /// Stops listening and lets go of the VM, which the server otherwise keeps alive on the VM's queue.
    func stop() {
        let stopSelector = NSSelectorFromString("stop")
        if server.responds(to: stopSelector) { server.perform(stopSelector) }
        if server.responds(to: NSSelectorFromString("setVirtualMachine:")) { server.setValue(nil, forKey: "virtualMachine") }
    }

    /// The loopback port, once the server is listening.
    var port: UInt16? {
        let value = (server.value(forKey: "port") as? NSNumber)?.uint16Value ?? 0
        return value == 0 ? nil : value
    }
}
