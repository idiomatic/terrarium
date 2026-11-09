import Foundation

/// Installs the guest helper into a freshly provisioned macOS guest over SSH, at the guest's NAT address.
/// The address comes from the host's DHCP leases, by the guest's MAC address; the account's password answers SSH through
/// `SSH_ASKPASS` and `sudo -S`, never on an argument list.
enum MacHelperInstall {
    static let leases = "/var/db/dhcpd_leases"

    /// Waits up to `timeout` seconds for the guest to come up, then installs and starts the helper.
    static func run(mac: String, account: MacPlan.Account, helper: Data, in directory: URL, timeout: TimeInterval = 1500) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var address: String?
        while address == nil {
            guard Date() < deadline else { throw CLIError.failure("the macOS guest never got a network address") }
            address = leaseAddress(mac: mac)
            if address == nil { Thread.sleep(forTimeInterval: 3) }
        }
        note("the macOS guest is at \(address!); waiting for Remote Login")

        let askpass = directory.appendingPathComponent("askpass.sh")
        try Data("#!/bin/sh\nprintf '%s\\n' \"$TERRARIUM_PASSWORD\"\n".utf8).write(to: askpass)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askpass.path)
        defer { try? FileManager.default.removeItem(at: askpass) }
        let environment = ["SSH_ASKPASS": askpass.path, "SSH_ASKPASS_REQUIRE": "force", "DISPLAY": ":0", "TERRARIUM_PASSWORD": account.password]
        let options = [
            "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-o", "LogLevel=ERROR",
            "-o", "PreferredAuthentications=password,keyboard-interactive", "-o", "PubkeyAuthentication=no",
            "-o", "NumberOfPasswordPrompts=1", "-o", "ConnectTimeout=10",
        ]
        let target = "\(account.username)@\(address!)"
        func ssh(_ command: String, input: Data = Data()) throws -> Data {
            try runProgram("/usr/bin/ssh", options + [target, command], environment: environment, input: input)
        }

        while true {
            do {
                _ = try ssh("true")
                break
            } catch {
                guard Date() < deadline else { throw CLIError.failure("cannot log in to the macOS guest over SSH: \((error as? CLIError)?.message ?? "\(error)")") }
                Thread.sleep(forTimeInterval: 5)
            }
        }

        note("installing the helper")
        let staging = directory.appendingPathComponent("helper-staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let files = [("terrarium-helper", helper), ("terrarium-helper.plist", Data(plist.utf8)), ("terrarium-install.sh", Data(installScript.utf8))]
        for (name, contents) in files { try contents.write(to: staging.appendingPathComponent(name)) }
        try runProgram("/usr/bin/scp", options + files.map { staging.appendingPathComponent($0.0).path } + ["\(target):/tmp/"], environment: environment)
        _ = try ssh("sudo -S -p '' sh /tmp/terrarium-install.sh \(account.username) && rm -f /tmp/terrarium-helper /tmp/terrarium-helper.plist /tmp/terrarium-install.sh",
                    input: Data((account.password + "\n").utf8))
        note("the helper is running in the macOS guest")
    }

    /// The IP address leased to a MAC address, from the host's DHCP leases: blocks of `key=value` lines, with `hw_address`
    /// written as `1,a:b:c:d:e:f` (octets without leading zeros).
    static func leaseAddress(mac: String, text: String? = nil) -> String? {
        guard let text = text ?? (try? String(contentsOfFile: leases, encoding: .utf8)) else { return nil }
        func octets(_ s: String) -> [Int] { s.split(separator: ":").compactMap { Int($0, radix: 16) } }
        let wanted = octets(mac)
        var found: String?
        for block in text.components(separatedBy: "}") {
            var address: String?
            var hardware: [Int] = []
            for line in block.split(separator: "\n") {
                let parts = line.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                if parts[0] == "ip_address" { address = parts[1] }
                if parts[0] == "hw_address" { hardware = octets(String(parts[1].split(separator: ",").last ?? "")) }
            }
            if hardware == wanted, let address { found = address }
        }
        return found
    }

    private static let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>dev.terrarium.helper</string>
            <key>ProgramArguments</key><array><string>/usr/local/bin/terrarium-helper</string></array>
            <key>RunAtLoad</key><true/>
            <key>KeepAlive</key><true/>
            <key>StandardErrorPath</key><string>/tmp/terrarium-helper.log</string>
        </dict>
        </plist>

        """

    private static let installScript = """
        set -e
        user=$1
        uid=$(id -u "$user")
        printf '%s ALL=(ALL) NOPASSWD: ALL\\n' "$user" > /etc/sudoers.d/terrarium
        chmod 440 /etc/sudoers.d/terrarium
        visudo -cf /etc/sudoers.d/terrarium >/dev/null || { rm -f /etc/sudoers.d/terrarium; exit 1; }
        mkdir -p /usr/local/bin
        install -m 755 /tmp/terrarium-helper /usr/local/bin/terrarium-helper
        codesign --force --sign - /usr/local/bin/terrarium-helper
        install -m 644 -o root -g wheel /tmp/terrarium-helper.plist /Library/LaunchAgents/dev.terrarium.helper.plist
        launchctl bootout gui/$uid/dev.terrarium.helper 2>/dev/null || true
        n=0
        until launchctl print gui/$uid >/dev/null 2>&1; do
            n=$((n + 1))
            [ $n -lt 120 ] || { echo "$user has no GUI session" >&2; exit 1; }
            sleep 1
        done
        launchctl bootstrap gui/$uid /Library/LaunchAgents/dev.terrarium.helper.plist 2>/dev/null ||
            launchctl kickstart -k gui/$uid/dev.terrarium.helper

        """
}
