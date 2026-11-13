import Foundation
import ObjectiveC
import Virtualization

/// The only use of private Virtualization API: `_VZVNCServer`, which gives `terrarium` a framebuffer to read and an input
/// path. It listens on every address and takes none to bind, so any machine on the network, and any guest through its
/// gateway, can reach it: it therefore asks for VNC authentication, with a random password that only this process knows.
/// Every selector is checked first.
final class PrivateVNC {
    private let server: NSObject

    /// The password of this process's VNC server, which `RFB` answers the server's challenge with. A process serves one VM.
    nonisolated(unsafe) private static var password = ""
    private static let passwordLock = NSLock()

    static var currentPassword: String { passwordLock.withLock { password } }

    /// Starts the server for a running VM, or returns nil if this macOS does not have it, or cannot secure it.
    init?(_ vm: VZVirtualMachine) {
        guard let serverClass = NSClassFromString("_VZVNCServer") as? NSObject.Type,
              let securityClass = NSClassFromString("_VZVNCAuthenticationSecurityConfiguration") as? NSObject.Type else { return nil }
        let initSelector = NSSelectorFromString("initWithPort:queue:securityConfiguration:")
        let passwordSelector = NSSelectorFromString("initWithPassword:")
        let startSelector = NSSelectorFromString("start")
        // The keys used below through key-value coding are checked too: a missing one would raise, not return nil.
        guard serverClass.instancesRespond(to: initSelector), serverClass.instancesRespond(to: startSelector),
              serverClass.instancesRespond(to: NSSelectorFromString("setVirtualMachine:")),
              serverClass.instancesRespond(to: NSSelectorFromString("port")),
              securityClass.instancesRespond(to: passwordSelector),
              let raw = serverClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              let rawSecurity = securityClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() else { return nil }
        // VNC authentication uses the first eight characters: eight random letters and digits, new for every server.
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        let password = String((0..<8).map { _ in alphabet[Int(arc4random_uniform(UInt32(alphabet.count)))] })
        typealias InitPassword = @convention(c) (AnyObject, Selector, NSString) -> AnyObject
        let makeSecurity = unsafeBitCast(class_getMethodImplementation(securityClass, passwordSelector), to: InitPassword.self)
        let security = makeSecurity(rawSecurity, passwordSelector, password as NSString)
        Self.passwordLock.withLock { Self.password = password }
        typealias Init = @convention(c) (AnyObject, Selector, UInt16, DispatchQueue, AnyObject) -> AnyObject
        let make = unsafeBitCast(class_getMethodImplementation(serverClass, initSelector), to: Init.self)
        server = make(raw, initSelector, 0, vm.queue, security) as! NSObject
        server.setValue(vm, forKey: "virtualMachine")
        server.perform(startSelector)
    }

    /// Stops listening and lets go of the VM, which the server otherwise keeps alive on the VM's queue.
    func stop() {
        let stopSelector = NSSelectorFromString("stop")
        if server.responds(to: stopSelector) { server.perform(stopSelector) }
        if server.responds(to: NSSelectorFromString("setVirtualMachine:")) { server.setValue(nil, forKey: "virtualMachine") }
    }

    /// The server's port, once it is listening.
    var port: UInt16? {
        let value = (server.value(forKey: "port") as? NSNumber)?.uint16Value ?? 0
        return value == 0 ? nil : value
    }
}
