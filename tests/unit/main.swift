import Foundation
@testable import TerrariumCore

// Unit checks of the core's pure helpers, through `@testable import` of `TerrariumCore` (`zig build test`).

var failures = 0

func check(_ label: String, _ ok: Bool, _ detail: @autoclosure () -> Any = "") {
    print((ok ? "PASS " : "FAIL ") + label + (ok ? "" : "  -> \(detail())"))
    if !ok { failures += 1 }
}

// MARK: DHCP leases

let leases = """
{
    name=old
    ip_address=192.168.64.5
    hw_address=1,a:b:c:d:e:f
    lease=0x1
}
{
    name=other
    ip_address=192.168.64.6
    hw_address=1,1:2:3:4:5:6
    lease=0x2
}
{
    name=new
    ip_address=192.168.64.7
    hw_address=1,a:b:c:d:e:f
    lease=0x3
}
"""
check("a lease is found by MAC address, written with leading zeros", MacHelperInstall.leaseAddress(mac: "0a:0b:0c:0d:0e:0f", text: leases) == "192.168.64.7")
check("the last lease for a MAC address wins", MacHelperInstall.leaseAddress(mac: "a:b:c:d:e:f", text: leases) == "192.168.64.7")
check("an unknown MAC address has no lease", MacHelperInstall.leaseAddress(mac: "aa:bb:cc:dd:ee:ff", text: leases) == nil)

// MARK: WIM edition index

func wim(_ xml: String) throws -> URL {
    var body = Data([0xFF, 0xFE]) + xml.data(using: .utf16LittleEndian)!
    var header = Data(count: 208)
    header.replaceSubrange(0..<8, with: Data("MSWIM\0\0\0".utf8))
    func put(_ value: Int, at offset: Int, bytes: Int) {
        for i in 0..<bytes { header[offset + i] = UInt8(value >> (8 * i) & 0xFF) }
    }
    put(body.count, at: 72, bytes: 7)
    header[79] = 0
    put(208, at: 80, bytes: 8)
    put(body.count, at: 88, bytes: 8)
    body = header + body
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("terrarium-unit-\(UUID().uuidString).wim")
    try body.write(to: url)
    return url
}
let editions = """
<WIM><IMAGE INDEX="1"><WINDOWS><EDITIONID>Core</EDITIONID></WINDOWS></IMAGE>\
<IMAGE INDEX="2"><WINDOWS><EDITIONID>Education</EDITIONID></WINDOWS></IMAGE>\
<IMAGE INDEX="3"><WINDOWS><EDITIONID>Professional</EDITIONID></WINDOWS></IMAGE></WIM>
"""
do {
    let withPro = try wim(editions)
    defer { try? FileManager.default.removeItem(at: withPro) }
    check("the WIM's Professional edition is chosen", try Recipe.wimEditionIndex(withPro) == 3)
    let withoutPro = try wim(editions.replacingOccurrences(of: "Professional", with: "Enterprise"))
    defer { try? FileManager.default.removeItem(at: withoutPro) }
    check("without a Professional edition, the first image is chosen", try Recipe.wimEditionIndex(withoutPro) == 1)
    let notWim = FileManager.default.temporaryDirectory.appendingPathComponent("terrarium-unit-\(UUID().uuidString).wim")
    try Data(count: 208).write(to: notWim)
    defer { try? FileManager.default.removeItem(at: notWim) }
    check("a file that is not a WIM is refused", (try? Recipe.wimEditionIndex(notWim)) == nil)
} catch {
    check("synthetic WIM files", false, error)
}

// MARK: Windows answer file

check("markup characters are escaped", Recipe.xmlEscaped(#"a&b<c>d"e'f"#) == "a&amp;b&lt;c&gt;d&quot;e&apos;f")
let answer = Recipe.answerFile("<p>@PASS@</p><o>@EULA@</o>", password: "x@EULA@&", acceptLicense: true)
check("a password holding a placeholder is kept as given", answer.contains("<p>x@EULA@&amp;</p>"), answer)
check("the license placeholder is filled once, outside the password", answer.contains("<o><HideEULAPage>true</HideEULAPage>"), answer)
check("without --accept-license the placeholder is empty", Recipe.answerFile("<o>@EULA@</o>", password: "p", acceptLicense: false) == "<o></o>")

let named = Recipe.answerFile("<n>@USER@</n><u>@USER@</u>", user: "art", password: "p", acceptLicense: false)
check("the user name fills every placeholder in the answer file", named == "<n>art</n><u>art</u>", named)
check("the default user is terra", Recipe.answerFile("@USER@", password: "p", acceptLicense: false) == "terra")
check("ordinary user names are accepted", ["art", "_svc", "A-b_9", String(repeating: "a", count: 20)].allSatisfy { Recipe.userNameProblem($0) == nil })
check("empty, long, spaced, leading-digit, and non-ASCII names are refused",
      ["", String(repeating: "a", count: 21), "a b", "1a", "-a", "é", "a\"b", "a<b"].allSatisfy { Recipe.userNameProblem($0) != nil })
check("system account names are refused in any case", ["root", "Administrator", "GUEST"].allSatisfy { Recipe.userNameProblem($0) != nil })

// MARK: recipes

for recipe in [Recipe.install("alpine"), .install("windows"), .provision("alpine"), .provision("cloud-init"), .provision("nocloud")] {
    check("\(recipe.encoded) round-trips", Recipe(encoded: recipe.encoded) == recipe)
}
check("--provision nocloud is accepted", (try? Recipe.parse(install: nil, provision: "nocloud")) == .provision("nocloud"))
check("an unknown provision recipe is refused", (try? Recipe.parse(install: nil, provision: "bogus")) == nil)
check("--install and --provision together are refused", (try? Recipe.parse(install: "alpine", provision: "alpine")) == nil)
let helper = Data((0..<300).map { UInt8($0 & 0xFF) })
let userData = Recipe.cloudInitUserData(helper: helper)
check("cloud-init user-data is a cloud-config", userData.hasPrefix("#cloud-config\n"), userData.prefix(40))
check("it carries the helper, base64", userData.contains("content: \(helper.base64EncodedString())\n"))
check("and enables the helper's unit", userData.contains("systemctl enable --now terrarium-helper.service"))
check("and has an OpenRC service for guests without systemd", userData.contains("path: /usr/local/lib/terrarium-helper.initd\n") && userData.contains("      #!/sbin/openrc-run\n") && userData.contains("rc-service terrarium-helper start"))
check("and limits cloud-init to NoCloud on those, so a later boot without CIDATA does not wait", userData.contains("datasource_list: [ NoCloud, None ]"))

// MARK: input

func keys(_ events: [(UInt32, Bool)]) -> [String] { events.map { String(format: "%@%x", $0.1 ? "+" : "-", $0.0) } }
do {
    let plus = try Input.chord("ctrl++")
    check("ctrl++ names the plus key under Control", plus.first.map { $0 == (0xffe3, true) } == true && plus.contains { $0.0 == 0x3d || $0.0 == 0x2b }, keys(plus))
    check("a chord of only '+' is the plus key", (try? Input.chord("+")) != nil)
    check("a chord ending in a lone '+' after a modifier still needs a key", (try? Input.chord("ctrl+")) == nil)
    let crlf = try Input.text("a\r\nb\rc")
    check("CRLF and CR type Return", crlf.filter { $0 == (0xff0d, true) }.count == 2, keys(crlf))
} catch {
    check("input", false, error)
}

// MARK: exit statuses and names

check("a negated signal is 128 plus the signal", HelperProtocol.status(fromExit: -9) == 137)
check("-2^31 does not trap and stays as it is", HelperProtocol.status(fromExit: Int32.min) == Int32.min)
check("a Windows code stays whole", HelperProtocol.status(fromExit: 256) == 256)
check("the CLI exits 1 for codes outside 0 to 255", HelperProtocol.processStatus(256) == 1 && HelperProtocol.processStatus(-5) == 1 && HelperProtocol.processStatus(3) == 3)
let escaped = Pull.safeFileName(URL(string: "https://h/a/..%2F..%2Fx.img")!)
check("a URL's file name cannot hold a slash or start with a dot", !escaped.contains("/") && !escaped.hasPrefix("."), escaped)
check("a URL without a file name gets one", Pull.safeFileName(URL(string: "https://h/")!) == "download")

// MARK: tweaks

let header = Tweaks.header("#!/bin/sh\n# Does a thing: carefully.\n# timeout: 30\n# prose that is not a setting\n# Other-key: x y\necho hi\n# timeout: 99\n")
check("a tweak's first comment line is its description, even with a colon", header.description == "Does a thing: carefully.", header.description)
check("later key: value lines are settings; prose and capitalized keys are ignored", header.settings == ["timeout": "30"], header.settings)
check("a comment after the script's first command is not a setting", header.settings["timeout"] == "30")
check("a script with no comments has no description", Tweaks.header("echo hi\n").description.isEmpty)
let windowsScript = Tweaks.Script(tweak: Tweaks.catalog[0], text: "Write-Output 'é'", description: "", timeout: 10)
let encoded = windowsScript.argv.last.flatMap { Data(base64Encoded: $0) }.flatMap { String(data: $0, encoding: .utf16LittleEndian) }
check("a Windows tweak is PowerShell's -EncodedCommand, in UTF-16LE with progress off",
      windowsScript.argv.prefix(3) == ["powershell", "-NoProfile", "-NonInteractive"] && windowsScript.argv.contains("-EncodedCommand")
      && encoded == "$ProgressPreference = 'SilentlyContinue'\nWrite-Output 'é'", windowsScript.argv)
let shell = Tweaks.Script(tweak: Tweaks.Tweak(os: .linux, name: "t", section: "tw-t"), text: "echo hi\n", description: "", timeout: 10)
check("a Unix tweak is sh -c with the script", shell.argv == ["sh", "-c", "echo hi\n"], shell.argv)
check("a full name and a bare name find the same tweak", (try? Tweaks.resolve("windows/edge-quiet").name) == "edge-quiet" && (try? Tweaks.resolve("edge-quiet").os) == .windows)
func isUsageError(_ body: () throws -> Any) -> Bool {
    do { _ = try body(); return false } catch CLIError.usage { return true } catch { return false }
}
check("an unknown name is a usage error", isUsageError { try Tweaks.resolve("nosuch") })
check("a bare name two OSes have is ambiguous", isUsageError { try Tweaks.resolve("no-sleep") })
check("but the guest's own OS settles it", (try? Tweaks.resolve(["no-sleep"], for: .macos).first?.fullName) == "macos/no-sleep" && (try? Tweaks.resolve(["no-sleep"], for: .windows).first?.fullName) == "windows/no-sleep")
check("a tweak for another OS is refused", (try? Tweaks.resolve(["windows/edge-quiet"], for: .linux)) == nil)
check("and accepted for its own", (try? Tweaks.resolve(["edge-quiet"], for: .windows).count) == 1)
check("every catalog section name fits (16 characters)", Tweaks.catalog.allSatisfy { $0.section.utf8.count <= 16 })

// MARK: overlays over a guest

let guestDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("terrarium-unit-\(getpid())")
try? FileManager.default.createDirectory(at: guestDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: guestDirectory) }
let guestID = GuestManifest.newID()
check("a guest ID is 16 lowercase hex digits", guestID.count == 16 && guestID.allSatisfy { $0.isHexDigit && !$0.isUppercase }, guestID)
let guestPath = guestDirectory.appendingPathComponent("g.guest")
check("an overlay named for the guest passes", (try? checkOverlay(guestDirectory.appendingPathComponent("x-\(guestID).overlay"), guest: guestPath, id: guestID)) != nil)
check("one named for another guest is refused", (try? checkOverlay(guestDirectory.appendingPathComponent("x-0123456789abcdef.overlay"), guest: guestPath, id: guestID)) == nil)
check("a name without an ID skips the check", (try? checkOverlay(guestDirectory.appendingPathComponent("x.overlay"), guest: guestPath, id: guestID)) != nil)
check("an overlay over a guest is saved as PATH-<guestid>.overlay", Owner.saveTarget(guestDirectory.appendingPathComponent("x"), installed: false, image: guestID).lastPathComponent == "x-\(guestID).overlay")

// A layer over a guest's layer opens and reopens over it.
let blank = guestDirectory.appendingPathComponent("blank.img")
FileManager.default.createFile(atPath: blank.path, contents: nil)
try? FileHandle(forWritingTo: blank).truncate(atOffset: 1 << 30)
let guestRun = guestDirectory.appendingPathComponent("guest-run")
let overRun = guestDirectory.appendingPathComponent("over-run")
let againRun = guestDirectory.appendingPathComponent("again-run")
for directory in [guestRun, overRun, againRun] { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
let guestStack = try? openDisk(base: blank, overlay: nil, directory: guestRun)
let saved = guestDirectory.appendingPathComponent("saved.guest")
try? FileManager.default.createDirectory(at: saved, withIntermediateDirectories: true)
try? FileManager.default.copyItem(at: guestRun.appendingPathComponent(MacFiles.layer), to: saved.appendingPathComponent(MacFiles.layer))
let stacked = try? openDisk(base: blank, overlay: nil, directory: overRun, guestLayer: saved.appendingPathComponent(MacFiles.layer))
check("a guest's layer opens under a new layer", guestStack != nil && stacked?.layers.count == 3, stacked?.layers.count as Any)
let keep = guestDirectory.appendingPathComponent("keep.overlay")
try? FileManager.default.copyItem(at: overRun.appendingPathComponent(MacFiles.layer), to: keep)
let again = try? openDisk(base: blank, overlay: keep, directory: againRun, guestLayer: saved.appendingPathComponent(MacFiles.layer))
check("a saved overlay reopens over the guest", again?.layers.count == 3, again?.layers.count as Any)

print("\n\(failures) failure(s)")
exit(failures == 0 ? 0 : 1)
