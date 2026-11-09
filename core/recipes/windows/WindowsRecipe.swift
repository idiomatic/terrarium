import Foundation

/// The `--install windows` recipe. It installs: the VM boots a USB boot disk (the framebuffer shim, drivers, and
/// scripts) and USB installer media, and types a command over VNC that runs `install.cmd`, which installs onto the VM's
/// boot disk. The saved guest boots by its path and carries its own copy of the shim.
extension Recipe {
    /// The install target's default size in GB; `install.cmd` finds the disk by its size.
    static let windowsDiskSize = 40

    static func windows(image: Store.Image, user: String, password given: String?, acceptLicense: Bool, diskGB: Int, in directory: URL) throws -> Plan {
        let base = try blankDisk(gigabytes: diskGB, in: directory)
        guard let shim = Embedded.windowsShim, let helper = Embedded.helper(for: .windows) else {
            throw CLIError.failure("this terrarium has no Windows shim or helper")
        }

        let drivers = try virtioDriverDirectory()
        let installer = try installerMedia(for: image)

        let staging = directory.appendingPathComponent("recipe-staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let password = given ?? randomPassword()
        if given == nil {
            let passwordFile = directory.appendingPathComponent("windows-password")
            try Data((password + "\n").utf8).write(to: passwordFile)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: passwordFile.path)
            // The install's directory goes when the installer shuts the VM down, so this is the only time it is shown.
            note("Windows account: \(user), password \(password) (auto-logon is on)")
        } else {
            note("Windows account: \(user), with the password you gave (auto-logon is on)")
        }

        if acceptLicense {
            note("--accept-license: accepting Microsoft's Windows license terms (https://www.microsoft.com/useterms) for this install")
        } else {
            note("Windows will stop at Microsoft's license page; accept it yourself (shot, then click), or install again with --accept-license")
        }

        func stage(_ name: String, _ contents: Data) throws -> (path: String, source: URL) {
            let url = staging.appendingPathComponent(name.replacingOccurrences(of: "/", with: "_"))
            try contents.write(to: url)
            return (name, url)
        }
        func script(_ name: String, _ text: String) throws -> (path: String, source: URL) {
            try stage(name, Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8))
        }
        var entries = [
            try stage("EFI/BOOT/BOOTAA64.EFI", shim),
            try stage("terrarium-helper.exe", helper),
            try script("install.cmd", try assetText("win-install").replacingOccurrences(of: "@INDEX@", with: String(installer.index))
                .replacingOccurrences(of: "@DISKGB@", with: String(diskGB))),
            try script("unattend.xml", answerFile(try assetText("win-unattend"), user: user, password: password, acceptLicense: acceptLicense)),
            try script("SetupComplete.cmd", try assetText("win-setup").replacingOccurrences(of: "@USER@", with: user)),
        ]
        for case let file as URL in FileManager.default.enumerator(at: drivers, includingPropertiesForKeys: [.isRegularFileKey])! {
            guard (try file.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { continue }
            entries.append(("drivers/" + String(file.path.dropFirst(drivers.path.count + 1)), file))
        }
        note("building the boot disk")
        let boot = try fatMedia(named: "boot.img", volume: "TERRARIUM", size: "128m", entries: entries, in: directory)

        // Blind timing, as measured: spaces get past "Press any key"; Shift+F10 opens a prompt in WinPE; the disk is C:.
        var keys: [KeyStep] = [3, 6, 9, 12, 15].map { KeyStep(at: $0, action: .chord("space")) }
        keys.append(KeyStep(at: 62, action: .chord("shift+f10")))
        keys.append(KeyStep(at: 70, action: .text("C:\\install.cmd\n")))
        return Plan(
            kind: .windows,
            media: [Media(url: boot, readOnly: false), Media(url: installer.url, readOnly: true)],
            baseDisk: base,
            script: keys,
            installed: true,
            diskGB: diskGB,
            installCheck: .file(media: boot, marker: "install.ok", log: "install.log"))
    }

    /// The answer file from its template. The password goes in last, so no placeholder inside it is replaced.
    static func answerFile(_ template: String, user: String = Recipe.defaultUser, password: String, acceptLicense: Bool) -> String {
        template.replacingOccurrences(of: "@EULA@", with: acceptLicense ? eulaAccepted : "")
            .replacingOccurrences(of: "@USER@", with: xmlEscaped(user))
            .replacingOccurrences(of: "@PASS@", with: xmlEscaped(password))
    }

    /// The answer file is XML, so a given password's markup characters must be escaped.
    static func xmlEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }


    private static func assetText(_ section: String) throws -> String { String(decoding: try asset(section), as: UTF8.self) }

    /// What accepting the license adds to the answer file: Setup skips its OOBE pages, the license page included.
    private static let eulaAccepted = "<HideEULAPage>true</HideEULAPage><SkipMachineOOBE>true</SkipMachineOOBE><SkipUserOOBE>true</SkipUserOOBE>"
}
