import Foundation
import MachO

enum GuestOS: String {
    case macos
    case linux
    case windows
}

/// The guest helpers and the Windows shim that `build.zig` links into the `__TERRARIUM` segment.
enum Embedded {
    static func helper(for os: GuestOS) -> Data? { section(os.rawValue) }

    /// The Windows framebuffer shim, an EFI application.
    static var windowsShim: Data? { section("winfb") }

    static func section(_ name: String) -> Data? {
        var size: UInt = 0
        let header = #dsohandle.assumingMemoryBound(to: mach_header_64.self)
        guard let bytes = getsectiondata(header, "__TERRARIUM", name, &size) else { return nil }
        return Data(bytes: bytes, count: Int(size))
    }
}
