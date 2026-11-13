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
    /// Other command-line names for the option (not MCP argument names).
    public var aliases: [String] = []
}

public struct Verb {
    public let name: String
    public let summary: String
    public var positionals: [Param] = []
    public var options: [Option] = []
    /// The last positional is followed by arguments taken verbatim.
    public var passthrough: String?
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
    "combustion",
    "nocloud",
]

public let chordModifiers: Set<String> = ["ctrl", "shift", "alt", "win"]

/// Shared by `start` and `run`.
let vmParam = Param(name: "vm", metavar: "VM", help: "a running VM: its ID, or a unique prefix of it")
let bootPositionals = [Param(name: "image", metavar: "IMAGE|LAYER", help: "a stored image, or a layer (a name in the layer store, or the path of a .layer bundle; a layer takes no --install or --provision)", optional: true)]
let bootOptions = [
    Option(name: "memory", metavar: "MB", help: "memory in MiB (default 4096; 8192 for Windows and macOS)", kind: .integer),
    Option(name: "cpus", metavar: "N", help: "CPU count (default: this Mac's, up to 4)", kind: .integer),
    Option(name: "disk", metavar: "GB", help: "the new guest's disk size in GB with --install (default 4 for alpine, 40 for macos and windows, which is also the least; at most 1000); the disk is sparse, using only what the guest writes (a clean Windows install takes about 16 GB)", kind: .integer),
    Option(name: "user", metavar: "USERNAME", help: "the account to create with --install: Windows always has one (default terra); macOS has one only with this and --accept-license"),
    Option(name: "password", metavar: "PW", help: "the guest account's password with --install, or root's with --provision nocloud (default: random); `-` reads it from standard input, for run only"),
    Option(name: "accept-license", metavar: nil, help: "accept the guest vendor's license with --install windows or macos; without it Setup stops at the license page"),
    Option(name: "install", metavar: "RECIPE", help: "install IMAGE, an installer, onto a new guest: \(installRecipes.joined(separator: ", "))", kind: .choice(installRecipes)),
    Option(name: "provision", metavar: "RECIPE", help: "provision a live image's guest so it can be driven: \(provisionRecipes.joined(separator: ", "))", kind: .choice(provisionRecipes)),
    Option(name: "ephemeral", metavar: nil, help: "discard the VM's work when it stops (unless a commit saved it); start needs this or one of --save, --clone, and --continue, which are alternatives"),
    Option(name: "save", metavar: "CHILDLAYER", help: "when the VM stops, save its work as the new layer CHILDLAYER, a child of what it started from (an install: a root layer)"),
    Option(name: "clone", metavar: "SIBLINGLAYER", help: "with a layer: when the VM stops, save the layer's changes and the VM's as a copy, the sibling SIBLINGLAYER (also --save-sibling)", aliases: ["save-sibling"]),
    Option(name: "continue", metavar: nil, help: "with a layer: when the VM stops, save its work back to the layer, replacing it (also --save-over)", aliases: ["save-over"]),
    Option(name: "tweak", metavar: "TWEAK", help: "run this tweak in the guest once its helper answers, as the tweak verb does (repeatable): \(Tweaks.catalog.map(\.fullName).joined(separator: ", "))", repeatable: true),
    Option(name: "by", metavar: "NAME", help: "who starts the VM, for ps to show (1 to 64 printable ASCII characters, no spaces; default window for run, cli for start, and mcp:CLIENT:PID over MCP); a label, not a permission"),
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
            summary: "boot a stored image or a layer without a window and return; prints ID",
            positionals: bootPositionals,
            options: bootOptions),
        Verb(
            name: "run",
            summary: "boot a stored image or a layer in a window and stay until it closes; prints ID",
            positionals: bootPositionals,
            options: bootOptions,
            cliOnly: true),
        Verb(
            name: "commit",
            summary: "save the VM's delta as a layer, as the start options do (one of LAYER, --save, --clone, --continue, or --ephemeral), now or when it stops; prints the layer's path",
            positionals: [
                vmParam,
                Param(name: "layer", metavar: "LAYER", help: "shorthand for --save, or for --clone if the VM started with --clone or --continue: a name in the layer store, or a path (.layer is added)", optional: true),
            ],
            options: [
                Option(name: "save", metavar: "CHILDLAYER", help: "save a child of what the VM started from (not for a VM started with --clone or --continue)"),
                Option(name: "clone", metavar: "SIBLINGLAYER", help: "save a sibling of the starting layer, keeping its changes (only for a VM started with --clone or --continue; also --save-sibling)", aliases: ["save-sibling"]),
                Option(name: "continue", metavar: nil, help: "replace the starting layer (only for a VM started with --clone or --continue; also --save-over)", aliases: ["save-over"]),
                Option(name: "ephemeral", metavar: nil, help: "cancel a scheduled save: the VM's work is discarded when it stops"),
                Option(name: "on-stop", metavar: nil, help: "save when the VM stops instead of now"),
            ]),
        Verb(
            name: "stop",
            summary: "stop a VM, discarding its delta unless committed",
            positionals: [vmParam]),
        Verb(
            name: "ps",
            summary: "list running VMs",
            options: [Option(name: "deceased", metavar: nil, help: "list instead the last VMs that ended (at most 20), with their exit status and why")]),
    ]),
    ("layers", [
        Verb(name: "layers", summary: "list the layer store as a tree: images that have layers as roots, a layer under its parent"),
        Verb(
            name: "rm",
            summary: "remove a layer; layers made from it stay whole",
            positionals: [Param(name: "layer", metavar: "LAYER", help: "a name in the layer store, or a path")]),
        Verb(
            name: "squash",
            summary: "save NEWLAYER, one layer holding LAYER's changes and those of its ancestors above ANCESTOR, with no VM; LAYER is left as it is; prints the new layer's path",
            positionals: [
                Param(name: "layer", metavar: "LAYER", help: "the layer to squash: a name in the layer store, or a path"),
                Param(name: "newlayer", metavar: "NEWLAYER", help: "the layer to save, which must not exist: a name in the layer store, or a path (.layer is added)"),
            ],
            options: [Option(name: "onto", metavar: "ANCESTOR", help: "the layer or image in LAYER's chain that NEWLAYER is made from (default: the chain's root, so the whole chain is squashed)")]),
    ]),
    ("observe and control", [
        Verb(name: "shot", summary: "write a PNG of the screen to stdout", positionals: [vmParam]),
        Verb(
            name: "record",
            summary: "record the screen as a video until record --stop, the time limit, or the VM stops; prints the file, its length, and its frames when it ends",
            positionals: [
                vmParam,
                Param(name: "path", metavar: "PATH", help: "the video to write, .mov or .mp4, which must not exist (not with --stop)", optional: true),
            ],
            options: [
                Option(name: "stop", metavar: nil, help: "end the VM's recording and write its file"),
                Option(name: "fps", metavar: "N", help: "at most this many frames a second, 1 to 30 (default 10); a still screen adds none", kind: .integer),
                Option(name: "max-seconds", metavar: "N", help: "end the recording after this long (default 600)", kind: .integer),
                Option(name: "clicks", metavar: nil, help: "mark each click with a dot and a ring (the end of a drag with a ring), colored by button"),
                Option(name: "crop", metavar: "X,Y,W,H", help: "keep only this rectangle of the screen, in screenshot coordinates"),
            ]),
        Verb(name: "logs", summary: "print the VM's console log", positionals: [vmParam]),
        Verb(
            name: "click",
            summary: "click, drag, or scroll at screenshot coordinates",
            positionals: [vmParam, Param(name: "at", metavar: "X,Y", help: "pointer position", kind: .point)],
            options: [
                Option(name: "button", metavar: "B", help: "left, middle, or right (default left)", kind: .choice(["left", "middle", "right"])),
                Option(name: "drag-to", metavar: "X,Y", help: "drag to this position", kind: .point),
                Option(name: "scroll", metavar: "DX,DY", help: "scroll by this amount (positive: down, right)", kind: .point),
                Option(name: "duration", metavar: "MS", help: "glide the pointer to X,Y over this long before clicking, or with --drag-to, take this long to drag (at most 10000)", kind: .integer),
            ]),
        Verb(
            name: "move",
            summary: "move the pointer to screenshot coordinates without clicking",
            positionals: [vmParam, Param(name: "at", metavar: "X,Y", help: "pointer position", kind: .point)],
            options: [Option(name: "duration", metavar: "MS", help: "glide there over this long, eased in and out, rather than jump (at most 10000)", kind: .integer)]),
        Verb(
            name: "resize",
            summary: "ask the guest for a display of this size in pixels, as the window's Match Guest to Window does; a guest that ignores it changes nothing",
            positionals: [vmParam, Param(name: "size", metavar: "WxH", help: "width and height in pixels, like 1280x800")]),
        Verb(
            name: "type",
            summary: "type text",
            positionals: [vmParam, Param(name: "text", metavar: "TEXT", help: "text to type")],
            options: [Option(name: "interval", metavar: "MS", help: "pause this long after each character, as a person types (at most 1000)", kind: .integer)]),
        Verb(
            name: "key",
            summary: "press a key or chord, e.g. ctrl+shift+n",
            positionals: [vmParam, Param(name: "chord", metavar: "[CHORD+]KEY", help: "modifiers: \(chordModifiers.sorted().joined(separator: ", "))")]),
        Verb(
            name: "exec",
            summary: "run a command in the guest",
            positionals: [vmParam, Param(name: "command", metavar: "COMMAND", help: "program to run")],
            options: [Option(name: "timeout", metavar: "SECONDS", help: "kill the command and exit 124 after this long (default: no limit)", kind: .integer)],
            passthrough: "ARGS"),
        Verb(
            name: "tweak",
            summary: "run a tweak, an OS-specific script, in the guest; exits with its status",
            positionals: [vmParam, Param(name: "name", metavar: "TWEAK", help: "<os>/<name> or a bare <name>: \(Tweaks.catalog.map(\.fullName).joined(separator: ", "))")]),
        Verb(
            name: "wait",
            summary: "wait until the guest is ready to be driven: the VM is running, its tweaks are done, and its helper answers",
            positionals: [vmParam],
            options: [
                Option(name: "timeout", metavar: "SECONDS", help: "give up after this long (default 600)", kind: .integer),
                Option(name: "down", metavar: nil, help: "wait for the guest to go down instead: the VM has stopped, or its helper answered and no longer does"),
                Option(name: "reboot", metavar: nil, help: "wait for the guest to restart instead: its helper answers with a new instance ID, not the one the last wait found"),
            ]),
        Verb(
            name: "put",
            summary: "copy a file, or a directory's files, from this Mac into the guest; missing guest directories are made",
            positionals: [
                vmParam,
                Param(name: "from", metavar: "HOST_PATH", help: "a file, or a directory whose files go into DEST"),
                Param(name: "to", metavar: "GUEST_PATH", help: "the guest's absolute path (on Windows, with a drive letter)"),
            ]),
        Verb(
            name: "get",
            summary: "copy a file from the guest to this Mac, replacing the file there",
            positionals: [
                vmParam,
                Param(name: "from", metavar: "GUEST_PATH", help: "the guest's absolute path (on Windows, with a drive letter)"),
                Param(name: "to", metavar: "HOST_PATH", help: "a file to write, or a directory to put it in under its own name"),
            ]),
        Verb(
            name: "clipboard",
            summary: "get or set the guest's clipboard text; set types the text if the guest has no clipboard",
            positionals: [
                vmParam,
                Param(name: "action", metavar: "get|set", help: "read the guest's clipboard, or replace it", kind: .choice(["get", "set"])),
                Param(name: "text", metavar: "TEXT", help: "for set: the text (on the command line, - reads standard input)", optional: true),
            ]),
    ]),
]

public let allVerbs = verbGroups.flatMap(\.verbs)

public func findVerb(_ name: String) -> Verb? {
    allVerbs.first { $0.name == name }
}
