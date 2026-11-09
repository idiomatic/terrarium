import Foundation

/// Value kinds that the parser checks before a verb runs.
public enum Kind {
    case text
    case integer
    case point
    case choice([String])
}

public struct Param {
    public let name: String
    public let metavar: String
    public let help: String
    public var kind: Kind = .text
    public var optional = false
}

/// An option takes a value when `metavar` is set; otherwise it is a flag.
public struct Option {
    public let name: String
    public let metavar: String?
    public let help: String
    public var kind: Kind = .text
    /// May be given more than once; the values are in `Invocation.lists`.
    public var repeatable = false
}

public struct Verb {
    public let name: String
    public let summary: String
    public var positionals: [Param] = []
    public var options: [Option] = []
    /// The last positional is followed by arguments taken verbatim.
    public var passthrough: String?
    /// The verb acts on a running VM: the only one, or the one named by `--vm`.
    public var targetsVM = false
    /// Not exposed as an MCP tool.
    public var cliOnly = false
}

/// `--install` makes a guest from an installer image; `--provision` readies a live image or guest for driving.
let installRecipes = [
    "alpine",
    "macos",
    "windows",
]
let provisionRecipes = [
    "alpine",
    "cloud-init",
    "nocloud",
]

public let chordModifiers: Set<String> = ["ctrl", "shift", "alt", "win"]

/// Shared by `start` and `run`.
let bootPositionals = [Param(name: "image", metavar: "IMAGE|PATH.guest", help: "stored image, or an installed guest (a .guest directory, which takes no --install or --provision)", optional: true)]
let bootOptions = [
    Option(name: "memory", metavar: "MB", help: "memory in MiB (default 4096; 8192 for Windows and macOS)", kind: .integer),
    Option(name: "cpus", metavar: "N", help: "CPU count (default: this Mac's, up to 4)", kind: .integer),
    Option(name: "disk", metavar: "GB", help: "the new guest's disk size in GB with --install (default 4 for alpine, 40 for macos and windows, which is also the least; at most 1000)", kind: .integer),
    Option(name: "user", metavar: "NAME", help: "the account to create with --install: Windows always has one (default terra); macOS has one only with this and --accept-license"),
    Option(name: "password", metavar: "PW", help: "the guest account's password with --install, or root's with --provision nocloud (default: random); `-` reads it from standard input, for run only"),
    Option(name: "accept-license", metavar: nil, help: "accept the guest vendor's license with --install windows or macos; without it Setup stops at the license page"),
    Option(name: "overlay", metavar: "PATH", help: "start from a copy of this overlay, a layer over IMAGE or PATH.guest"),
    Option(name: "install", metavar: "RECIPE", help: "install IMAGE, an installer, onto a new guest: \(installRecipes.joined(separator: ", "))", kind: .choice(installRecipes)),
    Option(name: "provision", metavar: "RECIPE", help: "provision a live image's guest so it can be driven: \(provisionRecipes.joined(separator: ", "))", kind: .choice(provisionRecipes)),
    Option(name: "tweak", metavar: "NAME", help: "run this tweak in the guest once its helper answers, as the tweak verb does (repeatable): \(Tweaks.catalog.map(\.fullName).joined(separator: ", "))", repeatable: true),
]

public let verbGroups: [(title: String, verbs: [Verb])] = [
    ("images", [
        Verb(
            name: "pull",
            summary: "download, decompress, convert, hash, and store an image; prints IMAGE",
            positionals: [Param(name: "source", metavar: "URL|PATH", help: "where the image comes from")]),
        Verb(name: "images", summary: "list stored images"),
        Verb(
            name: "rmi",
            summary: "remove a stored image",
            positionals: [Param(name: "image", metavar: "IMAGE", help: "stored image")]),
    ]),
    ("lifecycle", [
        Verb(
            name: "start",
            summary: "boot a stored image without a window and return; prints ID",
            positionals: bootPositionals,
            options: bootOptions),
        Verb(
            name: "run",
            summary: "boot a stored image in a window and stay until it closes; prints ID",
            positionals: bootPositionals,
            options: bootOptions + [
                Option(name: "commit-on-stop", metavar: "PATH", help: "save the VM's overlay under this path prefix when the VM stops, as Commit When VM Stops… does (see commit)"),
            ],
            cliOnly: true),
        Verb(
            name: "commit",
            summary: "save the VM's overlay as PATH-<imagehash>.overlay (PATH-<guestid>.overlay over a guest); prints that path",
            positionals: [
                Param(name: "id", metavar: "ID", help: "running VM"),
                Param(name: "path", metavar: "PATH", help: "overlay path prefix"),
            ],
            options: [
                Option(name: "on-stop", metavar: nil, help: "save when the VM stops instead of now"),
            ]),
        Verb(
            name: "stop",
            summary: "stop a VM, discarding its overlay unless committed",
            positionals: [Param(name: "id", metavar: "ID", help: "running VM")]),
        Verb(name: "ps", summary: "list running VMs"),
    ]),
    ("observe and control", [
        Verb(name: "shot", summary: "write a PNG of the screen to stdout", targetsVM: true),
        Verb(name: "logs", summary: "print the VM's console log", targetsVM: true),
        Verb(
            name: "click",
            summary: "click, drag, or scroll at screenshot coordinates",
            positionals: [Param(name: "at", metavar: "X,Y", help: "pointer position", kind: .point)],
            options: [
                Option(name: "button", metavar: "B", help: "left, middle, or right (default left)", kind: .choice(["left", "middle", "right"])),
                Option(name: "drag-to", metavar: "X,Y", help: "drag to this position", kind: .point),
                Option(name: "scroll", metavar: "DX,DY", help: "scroll by this amount (positive: down, right)", kind: .point),
            ],
            targetsVM: true),
        Verb(
            name: "type",
            summary: "type text",
            positionals: [Param(name: "text", metavar: "TEXT", help: "text to type")],
            targetsVM: true),
        Verb(
            name: "key",
            summary: "press a key or chord, e.g. ctrl+shift+n",
            positionals: [Param(name: "chord", metavar: "[CHORD+]KEY", help: "modifiers: \(chordModifiers.sorted().joined(separator: ", "))")],
            targetsVM: true),
        Verb(
            name: "exec",
            summary: "run a command in the guest",
            positionals: [Param(name: "command", metavar: "COMMAND", help: "program to run")],
            passthrough: "ARGS",
            targetsVM: true),
        Verb(
            name: "tweak",
            summary: "run a tweak, an OS-specific script, in the guest; exits with its status",
            positionals: [Param(name: "name", metavar: "NAME", help: "<os>/<name> or a bare <name>: \(Tweaks.catalog.map(\.fullName).joined(separator: ", "))")],
            targetsVM: true),
        Verb(
            name: "clipboard",
            summary: "get or set the guest's clipboard text; set types the text if the guest has no clipboard",
            positionals: [
                Param(name: "action", metavar: "get|set", help: "read the guest's clipboard, or replace it", kind: .choice(["get", "set"])),
                Param(name: "text", metavar: "TEXT", help: "for set: the text (on the command line, - reads standard input)", optional: true),
            ],
            targetsVM: true),
    ]),
]

public let allVerbs = verbGroups.flatMap(\.verbs)

public func findVerb(_ name: String) -> Verb? {
    allVerbs.first { $0.name == name }
}
