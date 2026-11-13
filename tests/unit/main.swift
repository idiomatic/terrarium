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

for recipe in [Recipe.install("alpine"), .install("windows"), .provision("alpine"), .provision("cloud-init"), .provision("combustion"), .provision("nocloud")] {
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

// MARK: layers

let layerDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("terrarium-unit-\(getpid())")
try? FileManager.default.createDirectory(at: layerDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: layerDirectory) }
let savedSupport = Paths.support
Paths.support = layerDirectory.appendingPathComponent("support")
defer { Paths.support = savedSupport }
let layerID = LayerManifest.newID()
check("a layer ID is 16 lowercase hex digits", layerID.count == 16 && layerID.allSatisfy { $0.isHexDigit && !$0.isUppercase }, layerID)
check("a bare name is a layer in the store", !LayerStore.isPath("win") && LayerStore.location("win") == Paths.layers.appendingPathComponent("win.layer", isDirectory: true))
check("an argument with a slash, a tilde, or .layer is a path", LayerStore.isPath("a/b") && LayerStore.isPath("~/x") && LayerStore.isPath("x.layer"))
check("a path gets .layer once", LayerStore.location("/tmp/x").lastPathComponent == "x.layer" && LayerStore.location("/tmp/x.layer").lastPathComponent == "x.layer")
check("a chain file is named by position, id, and kind", ChainFile(id: "abc", url: layerDirectory, isImage: false).name(at: 2) == "2-abc.asif" && ChainFile(id: "img-0123456789abcdef", url: layerDirectory, isImage: true).name(at: 0) == "0-img-0123456789abcdef.img")

func makeBundle(_ name: String, chain: [String], files: [String]) throws -> URL {
    let bundle = layerDirectory.appendingPathComponent("\(name).layer", isDirectory: true)
    try FileManager.default.createDirectory(at: bundle.appendingPathComponent(LayerManifest.chainDirectory), withIntermediateDirectories: true)
    for file in files { FileManager.default.createFile(atPath: bundle.appendingPathComponent(LayerManifest.chainDirectory).appendingPathComponent(file).path, contents: Data()) }
    try LayerManifest(guest: "linux", diskGB: 4, installer: "installer", id: LayerManifest.newID(), chain: chain).write(to: bundle)
    return bundle
}
let whole = try? makeBundle("whole", chain: ["aaaa", "bbbb"], files: ["0-aaaa.asif", "1-bbbb.asif"])
let manifestRead = whole.flatMap { try? LayerManifest.read($0) }
check("a layer's manifest reads back", manifestRead?.chain == ["aaaa", "bbbb"] && manifestRead?.guest == "linux" && manifestRead?.version == LayerManifest.currentVersion)
check("its chain files are found, root first", whole.flatMap { w in manifestRead.flatMap { try? LayerStore.chainFiles(of: w, $0) } }?.map(\.id) == ["aaaa", "bbbb"])
let damaged = try? makeBundle("damaged", chain: ["aaaa", "bbbb"], files: ["0-aaaa.asif"])
let damagedManifest = damaged.flatMap { try? LayerManifest.read($0) }
check("a missing chain file is a damaged layer", damaged.flatMap { d in damagedManifest.map { (try? LayerStore.chainFiles(of: d, $0)) == nil } } == true)
let imageRooted = try? makeBundle("imaged", chain: ["alpine-0123456789abcdef"], files: ["0-alpine-0123456789abcdef.img"])
check("an image at the chain's root is told by its extension", imageRooted.flatMap { i in (try? LayerManifest.read(i)).flatMap { try? LayerStore.chainFiles(of: i, $0) } }?.first?.isImage == true)
let old = layerDirectory.appendingPathComponent("old.layer", isDirectory: true)
try? FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
try? Data(#"{"version":1,"guest":"windows","diskGB":40,"installer":"x","id":"0123456789abcdef"}"#.utf8).write(to: old.appendingPathComponent(LayerManifest.fileName))
check("a layer saved by an earlier terrarium is refused", (try? LayerManifest.read(old)) == nil)
check("a directory with no manifest is not a layer", (try? LayerManifest.read(layerDirectory)) == nil)

let target = layerDirectory.appendingPathComponent("t.layer", isDirectory: true)
check("a save into an existing directory passes", (try? Owner.checkSaveTarget(target, startedFrom: nil)) != nil)
try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
check("a save over an existing layer is refused", (try? Owner.checkSaveTarget(target, startedFrom: nil)) == nil)
check("unless the VM started from it with --clone or --continue", (try? Owner.checkSaveTarget(target, startedFrom: target)) != nil)
check("a save into a missing directory is refused", (try? Owner.checkSaveTarget(layerDirectory.appendingPathComponent("no/such/x.layer"), startedFrom: nil)) == nil)

let lockTarget = layerDirectory.appendingPathComponent("locked.layer", isDirectory: true)
check("a layer's name is free before a VM reserves it", LayerLock.isFree(lockTarget))
let held = try? LayerLock.acquire(lockTarget)
check("a VM reserves it", held != nil)
check("and then it is not free", !LayerLock.isFree(lockTarget))
check("a second reservation is refused, naming the layer", (try? LayerLock.acquire(lockTarget)) == nil)
if let held { LayerLock.release(held, lockTarget) }
check("releasing frees it and leaves no lock file", LayerLock.isFree(lockTarget) && !FileManager.default.fileExists(atPath: LayerLock.file(for: lockTarget).path))

// A chain of layers opens in order, and a delta opens over it.
let blank = layerDirectory.appendingPathComponent("blank.img")
FileManager.default.createFile(atPath: blank.path, contents: nil)
try? FileHandle(forWritingTo: blank).truncate(atOffset: 1 << 30)
let rootRun = layerDirectory.appendingPathComponent("root-run")
let childRun = layerDirectory.appendingPathComponent("child-run")
let keepRun = layerDirectory.appendingPathComponent("keep-run")
for directory in [rootRun, childRun, keepRun] { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
let rootStack = try? openDisk(base: blank, chain: [], keepDelta: nil, source: nil, directory: rootRun)
check("a root layer's delta opens over the base", rootStack?.layers.count == 2, rootStack?.layers.count as Any)
let rootDelta = layerDirectory.appendingPathComponent("root-delta.asif")
try? FileManager.default.copyItem(at: rootRun.appendingPathComponent(MacFiles.layer), to: rootDelta)
let childStack = try? openDisk(base: blank, chain: [rootDelta], keepDelta: nil, source: nil, directory: childRun)
check("a child's delta opens over its parent's", childStack?.layers.count == 3, childStack?.layers.count as Any)
let kept = try? openDisk(base: blank, chain: [], keepDelta: rootDelta, source: nil, directory: keepRun)
check("with a kept delta the VM's starts as a copy of the layer's", kept?.layers.count == 2 && FileManager.default.fileExists(atPath: keepRun.appendingPathComponent(MacFiles.layer).path), kept?.layers.count as Any)
let reopened = try? reopenDisk(base: blank, chain: [rootDelta], directory: childRun)
check("a VM's disk reopens over the same files", reopened?.layers.count == 3, reopened?.layers.count as Any)

// A VM snapshots the layer, so replacing the layer meanwhile changes nothing it reads.
let snapSource = layerDirectory.appendingPathComponent("snap.layer", isDirectory: true)
try? FileManager.default.createDirectory(at: snapSource.appendingPathComponent(LayerManifest.chainDirectory), withIntermediateDirectories: true)
try? LayerManifest(guest: "linux", diskGB: 4, installer: "x", id: "0123456789abcdef", chain: []).write(to: snapSource)
FileManager.default.createFile(atPath: snapSource.appendingPathComponent(LayerManifest.deltaFile).path, contents: Data("delta".utf8))
let snapRun = layerDirectory.appendingPathComponent("snap-run")
try? FileManager.default.createDirectory(at: snapRun, withIntermediateDirectories: true)
let snapshot = LayerManifest.snapshot(snapSource, in: snapRun)
check("a snapshot is a clone of the layer in the VM's directory", snapshot?.deletingLastPathComponent().lastPathComponent == Plan.pinnedDirectory, snapshot as Any)
try? FileManager.default.removeItem(at: snapSource)
check("and it holds the manifest and delta after the layer is removed", snapshot.flatMap { try? LayerManifest.read($0) }?.id == "0123456789abcdef" && snapshot.flatMap { try? Data(contentsOf: $0.appendingPathComponent(LayerManifest.deltaFile)) } == Data("delta".utf8))

// MARK: screen text

check("a prompt is found in OCR text, whatever the case and spacing", ScreenText.shows("password:", in: "localhost login: root Password :"))
check("and with a letter misread", ScreenText.shows("password:", in: "localhost login: root Passuord: -"))
check("a long phrase may miss two characters", ScreenText.shows("new root password", in: "■ please enter the nev root passvord (empty to skip)"))
check("a prompt that is not there is not found", !ScreenText.shows("password:", in: "localhost login: _"))
check("a short phrase must match whole", !ScreenText.shows("login:", in: "reached target login prompts"))
check("a screen with nothing on it shows nothing", !ScreenText.shows("press any key", in: ""))

// MARK: installer images

let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("terrarium-installer-\(getpid())")
try? FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
func storedImage(_ name: String, _ bytes: Data) -> Store.Image {
    let url = imageDirectory.appendingPathComponent(name)
    try? bytes.write(to: url)
    return Store.Image(name: name, url: url, size: bytes.count, onDisk: bytes.count, created: Date())
}
func utf16(_ text: String, bigEndian: Bool) -> Data { Data(text.utf16.flatMap { bigEndian ? [0, UInt8($0)] : [UInt8($0), 0] }) }
let zeros = Data(count: 4096)
check("a zip file is a macOS installer", Store.installer(storedImage("restore", Data([0x50, 0x4B, 0x03, 0x04]) + zeros)) == "macos")
check("an ISO listing install.wim in UTF-16 is a Windows installer", Store.installer(storedImage("win-le", zeros + utf16("install.wim", bigEndian: false) + zeros)) == "windows")
check("so is one with it in UTF-16 big endian", Store.installer(storedImage("win-be", zeros + utf16("install.wim", bigEndian: true) + zeros)) == "windows")
check("or in ASCII, in either case", Store.installer(storedImage("win-ascii", zeros + Data("INSTALL.WIM;1".utf8) + zeros)) == "windows")
check("any other image is not told from a live one", Store.installer(storedImage("other", zeros)) == nil)
try? FileManager.default.removeItem(at: imageDirectory)

// MARK: squash --onto

let imageChain = ["alpine-0123456789abcdef", "aaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbb"]
let imageFiles = [ChainFile(id: imageChain[0], url: URL(fileURLWithPath: "/x/0.img"), isImage: true)]
    + imageChain.dropFirst().map { ChainFile(id: $0, url: URL(fileURLWithPath: "/x/\($0).asif"), isImage: false) }
check("squash keeps the image at the root by default", (try? Squash.keptCount(nil, chain: imageChain, files: imageFiles)) == 1)
check("squash over a blank disk keeps nothing by default", (try? Squash.keptCount(nil, chain: ["cccccccccccccccc"], files: [ChainFile(id: "cccccccccccccccc", url: URL(fileURLWithPath: "/x/c.asif"), isImage: false)])) == 0)
check("--onto an id keeps the chain through it", (try? Squash.keptCount("aaaaaaaaaaaaaaaa", chain: imageChain, files: imageFiles)) == 2)
check("--onto the parent keeps the whole chain", (try? Squash.keptCount("bbbbbbbbbbbbbbbb", chain: imageChain, files: imageFiles)) == 3)
check("--onto something outside the chain is refused", (try? Squash.keptCount("dddddddddddddddd", chain: imageChain, files: imageFiles)) == nil)

// MARK: VNC authentication

// The expected answer is DES-ECB of bytes 0 to 15 under the key 0e86ceceeef64e26 ("password", each byte's bits reversed),
// as `openssl enc -des-ecb -nopad` computes it.
check("VNC authentication answers a challenge as RFC 6143 says",
      RFB.answer(Array(0..<16), password: "password") == [184, 102, 146, 65, 37, 200, 238, 187, 157, 235, 193, 219, 97, 197, 56, 226],
      RFB.answer(Array(0..<16), password: "password"))
check("a password is cut at eight characters", RFB.answer(Array(0..<16), password: "passwordXYZ") == RFB.answer(Array(0..<16), password: "password"))

// MARK: record

check("--crop takes four whole numbers", Remote.parseCrop("0, 40,1024,720") == [0, 40, 1024, 720])
check("--crop refuses a negative corner, a side under 16, and a wrong count",
      Remote.parseCrop("-1,0,100,100") == nil && Remote.parseCrop("0,0,15,100") == nil && Remote.parseCrop("0,0,100") == nil && Remote.parseCrop("a,b,c,d") == nil)
check("a frame of another shape is fitted with bars, centered", Recorder.fit(CGSize(width: 1000, height: 500), in: CGSize(width: 1000, height: 1000)) == CGRect(x: 0, y: 250, width: 1000, height: 500))
check("a frame of the same shape fills the output", Recorder.fit(CGSize(width: 2048, height: 1536), in: CGSize(width: 1024, height: 768)) == CGRect(x: 0, y: 0, width: 1024, height: 768))

print("\n\(failures) failure(s)")
exit(failures == 0 ? 0 : 1)
