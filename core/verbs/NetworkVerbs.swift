import Foundation

/// `network` and `addr`: named networks' definitions, and a VM's address on one (or on its NAT network).
enum NetworkVerbs {
    /// `network [NAME] [--subnet CIDR] [--reserve KEY=IP]... [--unreserve KEY]... [--remove]`: without NAME, lists the
    /// networks; with it, changes and shows one's definition. A change to a network that is up takes effect when it next
    /// starts, since vmnet cannot change a running network's reservations.
    static func network(_ inv: Invocation) throws -> String {
        guard let name = inv.values["name"] else {
            guard inv.values["subnet"] == nil, (inv.lists["reserve"] ?? []).isEmpty, (inv.lists["unreserve"] ?? []).isEmpty, !inv.flags.contains("remove") else {
                throw CLIError.usage("network takes NAME to change a network")
            }
            return list()
        }
        if let problem = Networks.networkNameProblem(name) { throw CLIError.usage(problem) }
        if inv.flags.contains("remove") {
            guard inv.values["subnet"] == nil, (inv.lists["reserve"] ?? []).isEmpty, (inv.lists["unreserve"] ?? []).isEmpty else {
                throw CLIError.usage("--remove takes no other option")
            }
            try Networks.remove(name)
            return "removed \(name)"
        }
        return try Networks.editing(name) {
            var definition = Networks.read(name) ?? Networks.Definition()
            let before = definition
            if let subnet = inv.values["subnet"] {
                guard let net = Networks.parseSubnet(subnet) else { throw CLIError.usage("--subnet takes A.B.C.D/N, N from 8 to 30, like 192.168.200.0/24") }
                definition.subnet = "\(Networks.formatIPv4(net.address))/\(net.prefix)"
            }
            for key in inv.lists["unreserve"] ?? [] {
                guard definition.reservations.removeValue(forKey: key) != nil else { throw CLIError.failure("network \(name) has no reservation for \(key)") }
            }
            for text in inv.lists["reserve"] ?? [] {
                let parts = text.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { throw CLIError.usage("--reserve takes KEY=IP, like client1=192.168.200.11") }
                if let problem = Networks.nameProblem(parts[0], "a network KEY") { throw CLIError.usage(problem) }
                guard let subnet = definition.subnet else {
                    throw CLIError.usage("network \(name) has no subnet yet: give --subnet with --reserve, or start a VM on it first, which records the one vmnet picks")
                }
                guard Networks.parseIPv4(parts[1]) != nil, Networks.contains(subnet, parts[1]) else {
                    throw CLIError.usage("\(parts[1]) is not a host address in network \(name)'s subnet \(subnet)")
                }
                if let other = definition.reservations.first(where: { $0.value == parts[1] && $0.key != parts[0] }) {
                    throw CLIError.usage("\(parts[1]) is already reserved for \(other.key) on network \(name)")
                }
                definition.reservations[parts[0]] = parts[1]
            }
            // A subnet changed under reservations must still hold them.
            if let subnet = definition.subnet, let outside = definition.reservations.first(where: { !Networks.contains(subnet, $0.value) }) {
                throw CLIError.usage("the reservation \(outside.key)=\(outside.value) is outside \(subnet): change it with --reserve, or drop it with --unreserve")
            }
            var notes: [String] = []
            if definition != before || !FileManager.default.fileExists(atPath: Networks.definitionURL(name).path) {
                try Networks.write(name, definition)
                if Networks.isUp(name) && definition != before { notes.append("network \(name) is up: the change takes effect when it next starts, once no VM is on it") }
            }
            return (describe(name, definition) + notes).joined(separator: "\n")
        }
    }

    /// What `network NAME` prints: the subnet, each reservation with its MAC, and the VMs on it now.
    private static func describe(_ name: String, _ definition: Networks.Definition) -> [String] {
        var lines = ["network \(name): \(definition.subnet ?? "subnet picked at the first start"), \(Networks.isUp(name) ? "up" : "down")"]
        for (key, ip) in definition.reservations.sorted(by: { $0.key < $1.key }) {
            lines.append("  reserve \(key)=\(ip) (MAC \(Networks.mac(network: name, key: key)))")
        }
        for vm in Runtime.list() {
            for entry in vm.networks ?? [] where entry.hasPrefix(name + ":") {
                lines.append("  VM \(vm.id) as \(entry.dropFirst(name.count + 1))")
            }
        }
        return lines
    }

    /// The networks, defined or up: name, subnet, whether up, and the VMs on each by KEY.
    private static func list() -> String {
        let names = Networks.names()
        guard !names.isEmpty else { return "" }
        let vms = Runtime.list()
        let rows = [["NETWORK", "SUBNET", "STATE", "RESERVED", "VMS"]] + names.map { name in
            let definition = Networks.read(name) ?? Networks.Definition()
            let on = vms.flatMap { vm in (vm.networks ?? []).filter { $0.hasPrefix(name + ":") }.map { "\($0.dropFirst(name.count + 1))=\(vm.id)" } }
            return [name, definition.subnet ?? "-", Networks.isUp(name) ? "up" : "down", String(definition.reservations.count), on.isEmpty ? "-" : on.joined(separator: ",")]
        }
        let widths = (0..<4).map { c in rows.map { $0[c].count }.max()! }
        return rows.map { row in
            row.enumerated().map { $0 == 4 ? $1 : $1.padding(toLength: widths[$0], withPad: " ", startingAt: 0) }.joined(separator: "  ")
        }.joined(separator: "\n")
    }

    /// `addr VM [NETWORK] [--timeout SECONDS]`: the VM's IPv4 address on NETWORK (default: its NAT network). The guest is
    /// asked first, through its helper, for the address on the NIC with that network's MAC; a guest with only a self-assigned
    /// `169.254.x` there for 15 s is an error at once. Without a helper, the newest unexpired DHCP lease for the MAC in the
    /// network's subnet. Waits until the timeout (default 60) for one.
    static func addr(_ inv: Invocation) throws -> String {
        let info = try Runtime.resolve(inv.values["vm"]!)
        let network = inv.values["network"] ?? "nat"
        let limit = inv.values["timeout"].flatMap { Int($0) } ?? 60
        guard let mac = info.macs?[network] else {
            if network == "nat" { throw CLIError.failure("VM \(info.id) has no NAT address on record (it was started by an earlier terrarium)") }
            throw CLIError.failure("VM \(info.id) is not on network \(network)")
        }
        let subnet = network == "nat" ? nil : Networks.read(network)?.subnet
        let deadline = Date().addingTimeInterval(TimeInterval(limit))
        var selfAssignedSince: Date?
        while true {
            // Each look at the guest ends by the deadline, so `--timeout` holds.
            let left = max(1, Int(deadline.timeIntervalSinceNow.rounded(.up)))
            if let found = guestAddresses(info, timeout: min(20, left)) {
                let mine = found.filter { $0.mac == normalized(mac) }.map(\.ip)
                if let ip = mine.first(where: { ip in !ip.hasPrefix("169.254.") && (subnet.map { Networks.contains($0, ip) } ?? true) }) { return ip }
                if mine.contains(where: { $0.hasPrefix("169.254.") }) {
                    selfAssignedSince = selfAssignedSince ?? Date()
                    if Date().timeIntervalSince(selfAssignedSince!) >= 15 {
                        throw CLIError.failure("VM \(info.id) has no DHCP lease on \(network): the guest gave itself \(mine.first { $0.hasPrefix("169.254.") }!) (is the Mac's bootpd answering?)")
                    }
                }
            } else if let ip = Networks.lease(mac: mac, subnet: subnet) {
                return ip
            }
            guard Date() < deadline else {
                throw CLIError.failure("VM \(info.id) had no address on \(network) within \(limit) s")
            }
            sleep(1)
        }
    }

    /// A MAC as `aa:bb:cc:dd:ee:ff`, from any of the forms guests print (`AA-BB-…`, single-digit octets).
    static func normalized(_ mac: String) -> String {
        mac.lowercased().split(whereSeparator: { $0 == ":" || $0 == "-" }).map { $0.count == 1 ? "0" + $0 : String($0) }.joined(separator: ":")
    }

    /// Each IPv4 address the guest has, with its NIC's MAC, read through the helper; nil when the helper does not answer.
    private static func guestAddresses(_ info: Runtime.Info, timeout: Int) -> [(mac: String, ip: String)]? {
        let argv: [String]
        switch info.guest {
        case .windows:
            argv = ["powershell", "-NoProfile", "-NonInteractive", "-Command",
                    "Get-NetAdapter | ForEach-Object { $m = $_.MacAddress; Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { \"$m $($_.IPAddress)\" } }"]
        case .macos:
            // `ifconfig` can show a vmnet NIC's MAC as 02:00:00:00:00:00; `networksetup` has the one the VM gave it.
            argv = ["sh", "-c", "networksetup -listallhardwareports | awk '/^Device:/ { d = $2 } /^Ethernet Address:/ { print $3, d }' | while read -r m d; do a=$(ipconfig getifaddr \"$d\"); [ -n \"$a\" ] && echo \"$m $a\"; done; true"]
        case .linux, nil:
            argv = ["sh", "-c", "for i in /sys/class/net/*; do m=$(cat $i/address); ip -4 -o addr show dev ${i##*/} 2>/dev/null | while read -r _ _ _ a _; do echo \"$m ${a%/*}\"; done; done"]
        }
        guard let verb = findVerb("exec") else { return nil }
        var exec = Invocation(verb: verb)
        exec.values["vm"] = info.id
        exec.values["command"] = argv[0]
        exec.values["timeout"] = String(timeout)
        exec.rest = Array(argv.dropFirst())
        var output = Data()
        guard let status = try? Remote.stream(exec, sink: { stream, data in if stream == .stdout { output.append(data) } }), status == 0 else { return nil }
        // Windows ends its lines with CR.
        return String(decoding: output, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            return parts.count == 2 ? (normalized(parts[0]), parts[1]) : nil
        }
    }
}
