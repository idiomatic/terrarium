import CryptoKit
import Foundation
import Virtualization
import vmnet
import XPC

/// Named networks: host-only vmnet networks that VMs join with `--network NAME[:KEY]`, as a second NIC beside their NAT one.
/// A network lives only while a process holds it, so a detached holder, `terrarium __network NAME`, makes it and writes its
/// serialization to `networks/NAME.serial`, from which each VM's process rebuilds it. VMs hold a shared lock on
/// `.NAME.members` while on it, and the holder exits once none does. KEY names a VM's role: the NIC's MAC is derived from
/// the network and KEY, so a reservation for KEY gives it the same address at every start, and one KEY is one VM at a time.
enum Networks {
    /// What `network NAME` defines, in `networks/NAME.json`: the subnet (given, or recorded at the first start) and an
    /// address reserved for each KEY.
    struct Definition: Codable, Equatable {
        /// `A.B.C.D/N`, or nil until given or picked.
        var subnet: String?
        var reservations: [String: String] = [:]
    }

    /// A VM's place on a network, kept for the VM's life: the network, the NIC's MAC, and the locks that say the VM is there.
    final class Membership: @unchecked Sendable {
        let name: String
        let key: String
        let mac: String
        let network: vmnet_network_ref
        private let fds: [Int32]

        fileprivate init(name: String, key: String, mac: String, network: vmnet_network_ref, fds: [Int32]) {
            self.name = name
            self.key = key
            self.mac = mac
            self.network = network
            self.fds = fds
        }

        deinit { fds.forEach { close($0) } }

        /// A new attachment to the network, for a VM configuration (a restarted Windows guest gets a new one).
        func attachment() -> VZNetworkDeviceAttachment { VZVmnetNetworkDeviceAttachment(network: network) }
    }

    // MARK: names

    /// Why NAME cannot name a network or a KEY a role: 1 to 32 letters, digits, `_`, or `-`, starting with a letter or digit.
    static func nameProblem(_ name: String, _ what: String) -> String? {
        let allowed = name.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) || $0 == 0x2D || $0 == 0x5F }
        guard (1...32).contains(name.utf8.count), allowed, let first = name.utf8.first, first != 0x2D, first != 0x5F else {
            return "\(what) must be 1 to 32 letters, digits, _, or -, starting with a letter or digit: '\(name)'"
        }
        return nil
    }

    /// Why NAME cannot name a network: as `nameProblem` says, or `nat`, which names the VM's NAT network wherever a
    /// network is named (`addr VM nat`, `info.json`'s `macs`).
    static func networkNameProblem(_ name: String) -> String? {
        nameProblem(name, "a network's name") ?? (name == "nat" ? "nat names each VM's NAT network: give the network another name" : nil)
    }

    /// A KEY made from what a VM started from (a layer's or an image's name), for a `--network NAME` that gives none.
    static func defaultKey(from name: String) -> String {
        let mapped = String(name.unicodeScalars.map { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_") ? Character($0) : "-" })
        let trimmed = String(mapped.drop { $0 == "-" || $0 == "_" }.prefix(32))
        return trimmed.isEmpty ? "vm" : trimmed
    }

    /// `NAME[:KEY]`, the key defaulting to `defaultKey`.
    static func parseJoin(_ text: String, defaultKey key: String) throws -> (name: String, key: String) {
        let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let name = parts[0], given = parts.count > 1 ? parts[1] : key
        if let problem = networkNameProblem(name) { throw CLIError.usage(problem) }
        if let problem = nameProblem(given, "a network KEY") { throw CLIError.usage(problem) }
        return (name, given)
    }

    /// The NIC's MAC on network NAME for KEY: from a hash of both, locally administered and not multicast.
    static func mac(network name: String, key: String) -> String {
        var bytes = Array(SHA256.hash(data: Data("terrarium-network\u{0}\(name)\u{0}\(key)".utf8)).prefix(6))
        bytes[0] = (bytes[0] & 0xFC) | 0x02
        return bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    // MARK: subnets

    /// `A.B.C.D/N` as the network's address, its mask, and N (8 to 30); nil if malformed. The address is masked.
    static func parseSubnet(_ text: String) -> (address: UInt32, mask: UInt32, prefix: Int)? {
        let parts = text.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let prefix = Int(parts[1]), (8...30).contains(prefix), let address = parseIPv4(parts[0]) else { return nil }
        let mask = UInt32.max << (32 - prefix)
        return (address & mask, mask, prefix)
    }

    static func parseIPv4(_ text: String) -> UInt32? {
        let octets = text.split(separator: ".", omittingEmptySubsequences: false).map { UInt32($0) }
        guard octets.count == 4, octets.allSatisfy({ ($0 ?? 256) < 256 }) else { return nil }
        return octets.reduce(0) { $0 << 8 | $1! }
    }

    static func formatIPv4(_ value: UInt32) -> String { (0..<4).map { String(value >> (24 - 8 * $0) & 255) }.joined(separator: ".") }

    /// Whether `ip` is a host address in `subnet` (not its network or broadcast address).
    static func contains(_ subnet: String, _ ip: String) -> Bool {
        guard let net = parseSubnet(subnet), let address = parseIPv4(ip) else { return false }
        return address & net.mask == net.address && address != net.address && address != net.address | ~net.mask
    }

    // MARK: files

    static func definitionURL(_ name: String) -> URL { Paths.networks.appendingPathComponent("\(name).json") }
    static func serialURL(_ name: String) -> URL { Paths.networks.appendingPathComponent("\(name).serial") }
    static func logURL(_ name: String) -> URL { Paths.networks.appendingPathComponent("\(name).log") }
    private static func lockURL(_ name: String, _ kind: String) -> URL { Paths.networks.appendingPathComponent(".\(name).\(kind)") }

    static func read(_ name: String) -> Definition? {
        guard let data = try? Data(contentsOf: definitionURL(name)) else { return nil }
        return try? JSONDecoder().decode(Definition.self, from: data)
    }

    /// Runs `body` holding network NAME's definition for itself, so a read, change, and write of it is not lost to another's.
    static func editing<T>(_ name: String, _ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: Paths.networks, withIntermediateDirectories: true)
        guard let fd = try lockFile(lockURL(name, "definition").path, LOCK_EX) else { throw CLIError.failure("cannot edit network \(name)") }
        defer { close(fd) }
        return try body()
    }

    static func write(_ name: String, _ definition: Definition) throws {
        try FileManager.default.createDirectory(at: Paths.networks, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(definition).write(to: definitionURL(name), options: .atomic)
    }

    /// The defined networks' names, and those up (with a definition or not).
    static func names() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Paths.networks.path)) ?? []
        return Set(files.compactMap { $0.hasSuffix(".json") ? String($0.dropLast(5)) : $0.hasSuffix(".serial") ? String($0.dropLast(7)) : nil }).sorted()
    }

    /// Opens a lock file and takes `operation` on it without waiting; the descriptor, or nil if another holds it.
    private static func lock(_ url: URL, _ operation: Int32, contents: String? = nil) throws -> Int32? {
        try FileManager.default.createDirectory(at: Paths.networks, withIntermediateDirectories: true)
        guard let fd = try lockFile(url.path, operation | LOCK_NB) else { return nil }
        if let contents {
            ftruncate(fd, 0)
            _ = contents.withCString { pwrite(fd, $0, strlen($0), 0) }
        }
        return fd
    }

    /// Removes everything network NAME leaves: its definition, serialization, log, and lock files. Refused while it is up
    /// or a VM holds a KEY on it.
    static func remove(_ name: String) throws {
        guard !isUp(name) else { throw CLIError.failure("network \(name) is up: stop the VMs on it first") }
        // Held while the keys are looked at, so a VM refused meanwhile is told why.
        guard let removing = try lock(lockURL(name, "removing"), LOCK_EX) else { throw CLIError.failure("network \(name) is already being removed") }
        defer { close(removing) }
        let prefix = ".\(name)."
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Paths.networks.path)) ?? []
        for file in files where file.hasPrefix(prefix + "key.") {
            guard let fd = try lock(Paths.networks.appendingPathComponent(file), LOCK_EX) else {
                throw CLIError.failure("a VM is on network \(name) as \(file.dropFirst(prefix.count + 4)): stop it first")
            }
            close(fd)
        }
        let mine = files.filter { $0.hasPrefix(prefix) || [definitionURL(name), serialURL(name), logURL(name)].map(\.lastPathComponent).contains($0) }
        guard !mine.isEmpty else { throw CLIError.failure("no network \(name)") }
        for file in mine { try? FileManager.default.removeItem(at: Paths.networks.appendingPathComponent(file)) }
    }

    /// Whether a holder holds network NAME up now.
    static func isUp(_ name: String) -> Bool {
        // A network that never had a holder has no lock file, and looking does not make one.
        guard FileManager.default.fileExists(atPath: lockURL(name, "holder").path) else { return false }
        guard let fd = try? lock(lockURL(name, "holder"), LOCK_EX) else { return true }
        close(fd)
        return false
    }

    /// The holder's process ID, as it wrote it in its lock file.
    private static func holderPID(_ name: String) -> Int32? {
        (try? String(contentsOf: lockURL(name, "holder"), encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    // MARK: joining

    /// Why KEY's lock on network NAME is held: another VM is on it as KEY, or `network --remove` is looking.
    private static func keyRefusal(_ name: String, _ key: String) -> CLIError {
        let removing = lockURL(name, "removing")
        if FileManager.default.fileExists(atPath: removing.path) {
            guard let fd = try? lock(removing, LOCK_SH) else {
                return CLIError.failure("network \(name) is being removed: start the VM again once it is gone, or on another network")
            }
            close(fd)
        }
        let other = (try? String(contentsOf: lockURL(name, "key.\(key)"), encoding: .utf8)) ?? "another VM"
        return CLIError.failure("network \(name) already has a VM as \(key) (\(other)): give this one another KEY, as --network \(name):KEY")
    }

    /// Fails as `join` would when another VM is on network NAME as KEY, holding nothing: for `start` and `run` to check first.
    static func checkKey(_ name: String, key: String) throws {
        guard let fd = try lock(lockURL(name, "key.\(key)"), LOCK_EX) else {
            throw keyRefusal(name, key)
        }
        close(fd)
    }

    /// Puts this VM on network NAME as KEY: refuses a KEY another VM holds, starts the holder if the network is down, and
    /// rebuilds the network from its serialization. The membership keeps the locks until it is released.
    static func join(_ name: String, key: String, vm: String) throws -> Membership {
        guard let keyLock = try lock(lockURL(name, "key.\(key)"), LOCK_EX, contents: vm) else {
            throw keyRefusal(name, key)
        }
        var fds = [keyLock]
        do {
            // A shared lock that waits while a holder that found no members is ending.
            guard let members = try lockFile(lockURL(name, "members").path, LOCK_SH) else { throw CLIError.failure("cannot join network \(name)") }
            fds.append(members)
            let deadline = Date().addingTimeInterval(20)
            var spawned = Date.distantPast
            while Date() < deadline {
                let up = isUp(name)
                if up, let pid = holderPID(name), let network = rebuild(name, holder: pid) {
                    return Membership(name: name, key: key, mac: mac(network: name, key: key), network: network, fds: fds)
                }
                // A holder that has not come up within five seconds is tried again.
                if !up && Date().timeIntervalSince(spawned) > 5 {
                    _ = try spawnDetached(["__network", name], log: logURL(name))
                    spawned = Date()
                }
                usleep(200_000)
            }
            let log = (try? String(contentsOf: logURL(name), encoding: .utf8))?.split(separator: "\n").last.map(String.init) ?? ""
            // A holder that ended while VMs were on the network leaves them holding its subnet, so a new one cannot make it.
            let stranded = Runtime.list().filter { ($0.networks ?? []).contains { $0.hasPrefix(name + ":") } }.map(\.id)
            if log.contains("cannot make network"), !stranded.isEmpty {
                throw CLIError.failure("network \(name) is broken: its holder ended while VMs were on it, which keep its subnet; stop \(stranded.joined(separator: ", ")), then start again")
            }
            // A holder killed (SIGKILL) while VMs were on its network leaves vmnet holding the subnet after they stop.
            if log.contains("cannot make network") {
                throw CLIError.failure("vmnet will not make network \(name) on \(read(name)?.subnet ?? "its subnet"): a holder killed while VMs were on it leaves the subnet held, as long as tested (a restart of the Mac likely frees it); choose another with terrarium network \(name) --subnet CIDR")
            }
            throw CLIError.failure("network \(name) did not come up\(log.isEmpty ? "" : ": " + log)")
        } catch {
            fds.forEach { close($0) }
            throw error
        }
    }

    /// The network from its holder's serialization, when the file is that holder's.
    private static func rebuild(_ name: String, holder: Int32) -> vmnet_network_ref? {
        guard let data = try? Data(contentsOf: serialURL(name)),
              let saved = try? JSONDecoder().decode(Serial.self, from: data), saved.pid == holder else { return nil }
        let serial = xpc_dictionary_create(nil, nil, 0)
        for (key, value) in saved.fields {
            guard let bytes = Data(base64Encoded: value) else { return nil }
            bytes.withUnsafeBytes { xpc_dictionary_set_data(serial, key, $0.baseAddress!, $0.count) }
        }
        var status: vmnet_return_t = .VMNET_SUCCESS
        return vmnet_network_create_with_serialization(serial, &status)
    }

    /// The holder's serialization of the network: its data fields, base64, and the holder's process ID.
    private struct Serial: Codable {
        var pid: Int32
        var fields: [String: String]
    }

    // MARK: holding

    /// `__network NAME`: makes the network from its definition (recording the subnet vmnet picks, if none is given), writes
    /// its serialization, and holds it until no VM is on it. A second holder exits at once.
    static func hold(_ name: String) -> Never {
        func fail(_ message: String) -> Never {
            note("terrarium: \(message)")
            exit(1)
        }
        // A joiner looking to see whether the network is up holds the lock for an instant, so it is tried for a second;
        // a lock held that long is another holder's.
        var taken: Int32?
        for _ in 0..<10 where taken == nil {
            taken = try? lock(lockURL(name, "holder"), LOCK_EX, contents: String(getpid()))
            if taken == nil { usleep(100_000) }
        }
        guard let holder = taken else { exit(0) }
        var definition = read(name) ?? Definition()
        var status: vmnet_return_t = .VMNET_SUCCESS
        guard let config = vmnet_network_configuration_create(.VMNET_HOST_MODE, &status) else { fail("cannot configure network \(name) (vmnet \(status.rawValue))") }
        if let subnet = definition.subnet {
            guard let net = parseSubnet(subnet) else { fail("network \(name)'s subnet \(subnet) is not A.B.C.D/N") }
            // vmnet takes the host's address, the subnet's first host (`.1` of a /24), as it reports its own networks';
            // given the network's address, it makes a network on which no interface starts.
            var address = in_addr(s_addr: (net.address + 1).bigEndian), mask = in_addr(s_addr: net.mask.bigEndian)
            let set = vmnet_network_configuration_set_ipv4_subnet(config, &address, &mask)
            guard set == .VMNET_SUCCESS else { fail("vmnet refused network \(name)'s subnet \(subnet) (\(set.rawValue))") }
        }
        for (key, ip) in definition.reservations.sorted(by: { $0.key < $1.key }) {
            guard let value = parseIPv4(ip) else { fail("network \(name)'s reservation \(key)=\(ip) is not an IPv4 address") }
            var address = in_addr(s_addr: value.bigEndian)
            let octets = mac(network: name, key: key).split(separator: ":").map { UInt8($0, radix: 16)! }
            var ether = ether_addr_t(octet: (octets[0], octets[1], octets[2], octets[3], octets[4], octets[5]))
            let added = vmnet_network_configuration_add_dhcp_reservation(config, &ether, &address)
            guard added == .VMNET_SUCCESS else { fail("vmnet refused network \(name)'s reservation \(key)=\(ip) (\(added.rawValue))") }
        }
        guard let network = vmnet_network_create(config, &status) else { fail("cannot make network \(name) (vmnet \(status.rawValue))") }
        if definition.subnet == nil {
            var address = in_addr(), mask = in_addr()
            vmnet_network_get_ipv4_subnet(network, &address, &mask)
            let value = UInt32(bigEndian: address.s_addr), bits = UInt32(bigEndian: mask.s_addr)
            definition.subnet = "\(formatIPv4(value & bits))/\(bits.nonzeroBitCount)"
            // Read again, so a `network` change made meanwhile is kept; a subnet given meanwhile wins next time.
            let picked = definition.subnet
            try? editing(name) {
                var current = read(name) ?? Definition()
                guard current.subnet == nil else { return }
                current.subnet = picked
                try write(name, current)
            }
        }
        guard let serial = vmnet_network_copy_serialization(network, &status) else { fail("cannot share network \(name) (vmnet \(status.rawValue))") }
        var fields: [String: String] = [:]
        xpc_dictionary_apply(serial) { key, value in
            if let bytes = xpc_data_get_bytes_ptr(value) { fields[String(cString: key)] = Data(bytes: bytes, count: xpc_data_get_length(value)).base64EncodedString() }
            return true
        }
        do {
            let data = try JSONEncoder().encode(Serial(pid: getpid(), fields: fields))
            let partial = serialURL(name).appendingPathExtension("partial")
            FileManager.default.createFile(atPath: partial.path, contents: data, attributes: [.posixPermissions: 0o600])
            guard rename(partial.path, serialURL(name).path) == 0 else { throw CLIError.failure(String(cString: strerror(errno))) }
        } catch {
            fail("cannot write network \(name)'s serialization: \(error)")
        }
        note("network \(name) is up: \(definition.subnet ?? "?")")
        // Until no VM holds the members' lock: a VM takes it before it looks for the network, so none is missed.
        let members = lockURL(name, "members")
        while true {
            sleep(2)
            if let fd = try? lock(members, LOCK_EX) {
                try? FileManager.default.removeItem(at: serialURL(name))
                note("network \(name) is down: no VM is on it")
                withExtendedLifetime(network) {}
                close(fd)
                close(holder)
                exit(0)
            }
        }
    }

    // MARK: leases

    /// The newest unexpired lease in the host's DHCP leases for MAC, with its address in `subnet` when given (the file
    /// keeps hundreds of expired leases, and a derived MAC recurs across restarts and subnets); nil if none.
    static func lease(mac: String, subnet: String?, text: String? = nil, now: Date = Date()) -> String? {
        guard let text = text ?? (try? String(contentsOfFile: "/var/db/dhcpd_leases", encoding: .utf8)) else { return nil }
        func octets(_ s: String) -> [Int] { s.split(separator: ":").compactMap { Int($0, radix: 16) } }
        let wanted = octets(mac)
        var best: (address: String, expires: Double)?
        for block in text.components(separatedBy: "}") {
            var address: String?, hardware: [Int] = [], expires = 0.0
            for line in block.split(separator: "\n") {
                let parts = line.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                switch parts[0] {
                case "ip_address": address = parts[1]
                case "hw_address": hardware = octets(String(parts[1].split(separator: ",").last ?? ""))
                case "lease": expires = Double(UInt64(parts[1].hasPrefix("0x") ? String(parts[1].dropFirst(2)) : parts[1], radix: 16) ?? 0)
                default: break
                }
            }
            guard hardware == wanted, let address, expires > now.timeIntervalSince1970 else { continue }
            if let subnet, !contains(subnet, address) { continue }
            if best == nil || expires > best!.expires { best = (address, expires) }
        }
        return best?.address
    }
}
