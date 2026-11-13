# terrarium: a stdio MCP tool and CLI that drives macOS, Linux, and Windows guests from a Mac

* host `terrarium` in Swift (`core/`, `ui/`, `cli/`), on Virtualization framework, in three modules (see [modules](#modules)); guest code in Zig (`guest/`); checks in `tests/` (`zig build test`: the helper's frames, unit checks of the core's helpers in `tests/unit/`, MCP, and `pull`, in a temporary support directory; `live*.py` by hand); maintenance scripts in `tools/`, which generates [docs/distros.md](docs/distros.md) (see its [README](tools/README.md))
* guest `terrarium-helper` in Zig 0.17+, static, embedded in `terrarium`
* `zig build` builds the helpers (aarch64 macOS, Linux musl, and Windows), links them into `terrarium` (`__TERRARIUM` sections `macos`, `linux`, `windows`), the Windows shim and its guest scripts (`winfb`, `win-*`), embeds `cli/Info.plist` (`__TEXT,__info_plist`, so the menu bar says Terrarium), and signs it with the `com.apple.security.virtualization` entitlement
* CI (`.github/workflows/ci.yml`): `zig build` and `zig build test` on a hosted macOS 27 arm64 runner (`xcode-27`), skipped for a push or pull request that changes only `*.md`, `*.svg`, and `docs/` (never for a tag); the `live*.py` checks need VMs, which it cannot nest, and run by hand; a `v*` tag also publishes a release of the tested build (`terrarium-TAG-macos-aarch64.tar.gz` and its SHA-256), ad-hoc signed and not notarized, so the README says how to clear the browser's quarantine flag
* host: macOS 27+, aarch64; guests: macOS, Windows, Fedora, and Alpine (aarch64); see [docs/windows.md](docs/windows.md), [docs/macos.md](docs/macos.md), and the recipes' findings in [core/recipes](core/recipes/)
* external programs: any stock macOS program (never Homebrew or other installs), e.g. `diskutil`, `fsck_msdos`, `fsck_exfat`, `dot_clean`, `mdutil`, `codesign`, `gunzip`, `tar`, `rsync`, `ssh`, and `scp`; prefer `diskutil` over `hdiutil` and in-process APIs over programs; only to build, sign, and prepare images, and for `squash`, never in a running guest's path; read `--plist` output; no external libraries

## modules

* `TerrariumCore` (`core/`): everything but a front-end, with no AppKit: images, layers, recipes, VM configuration and state, the owner process as a headless engine (`Owner`), the control socket, the guest link, the display client, and the verb table with the code behind each verb (`Backend`)
* `TerrariumUI` (`ui/`): the `run` window, its menus, scale, and console log, over AppKit; it attaches to an `Owner` through the `OwnerUI` protocol, which the core calls on the main queue
* `terrarium` (`cli/`, with `cli/mcp/`, `cli/Info.plist`, and the entitlements): the executable, a command line and an MCP server over the core's verbs, which hands `run` the window
* `core/` is layered, lowest first: `system`; `images`, `display`, and `guestlink`; `vm`; `recipes` and `tweaks`; `owner`; `verbs`; a directory uses only those below it, and those of one rank do not use each other (`tests/layers.py`)
* the core's public surface is what the front-ends use: the verb table, `Invocation` and `invocation(_:arguments:)`, `Backend`, `Launch.start`, `Remote.exec`, `Owner` and `OwnerUI`, `Paths`, and `CLIError`; a front-end sets `Backend.windowFactory` to give `run` a window
* the support directory, `Paths.support`: the front-end sets it once at startup, before anything else in the core; the core reads no environment
* `terrarium` sets it from `$TERRARIUM_SUPPORT` when set (as the tests do), else `~/Library/Application Support/terrarium/`
* its children, each defined once in `Paths`: `images/`, `layers/`, `vms/`, `cache/`, `attached/`, and `unsaved/`

## verbs

Each verb is a CLI subcommand and an MCP tool of the same name and parameters, except `run` (CLI only).

* `terrarium version` or `terrarium --version` (CLI only; not a verb) prints `terrarium VERSION`, the version in `cli/Version.swift`, `cli/Info.plist`, and the MCP `serverInfo` (`tests/mcp.py` checks they agree); a release tag is `v` and VERSION, which CI checks

### images

* `pull URL|PATH` → downloads (if URL), decompresses, converts, hashes, and stores the image, cloning a local PATH where it can → IMAGE (see [image store](#image-store))
* `images` → lists stored images, each by its name without the hash unless another image has the same name (then `<name>-<hash>`), with the `--install` recipe it needs (INSTALL): `macos` for a restore image (a zip file), `windows` for an ISO whose first 16 MiB list `install.wim` (in ASCII or UTF-16, either case), else blank
* `rmi IMAGE` → removes a stored image

### layers

* `layers` → lists the [layer store](#layers) as a tree: images that have layers as roots, a layer under its parent, two spaces to a level; columns NAME, OS, DELTA (bytes the layer's own files take), and CHAIN (bytes of its cloned ancestors, shared with them); a layer whose parent is gone (removed, or saved elsewhere) is a root marked `(gone: ID)`; roots by name, children by creation time; a layer a running VM will save (`info.json` records `saveTo` and `saveParent`) is listed under the parent it will have, its DELTA the VM's delta so far, marked `(saved when VM ID stops)`, a layer it will replace is marked `(replaced when VM ID stops)`, and a target outside the store follows as an `also pending:` line
* `rm LAYER` → removes a layer; refused while a running VM started from it; layers made from it stay whole
* `squash LAYER NEWLAYER [--onto ANCESTOR]` → saves NEWLAYER, whose disk reads as LAYER's, with the chain up to ANCESTOR and one delta for the rest (see [squash](#squash)); LAYER is left as it is → NEWLAYER's path, the depth before and after, and the delta's bytes

### lifecycle

* `run [IMAGE|LAYER] [OPTIONS]` → ID; CLI only; foreground, shows the VM's display in a [window](#run-window)
* `start [IMAGE|LAYER] [OPTIONS]` → ID; hidden; returns at once, a background `terrarium` process keeps the VM
* `commit VM (LAYER | --save CHILDLAYER | --clone SIBLINGLAYER | --continue | --ephemeral) [--on-stop]` → the start options' own words, for a VM already running: saves the VM's delta as a layer now, or when the VM stops → LAYER' (see [layers](#layers)); `LAYER` alone is shorthand for `--save`, or for `--clone` when the VM started with `--clone` or `--continue`; `--save` is refused for such a VM (its delta already holds the layer's changes) and `--clone` and `--continue` for any other (its delta lacks them); `--ephemeral` cancels a scheduled save, releasing its name, so the work is discarded when the VM stops, and takes no `--on-stop`; exactly one of the five is given
* `stop VM` → returns once the VM has stopped and any scheduled commit is saved
* `ps [--deceased]` → running VMs, naming each image as `images` does, with who started each (BY; over MCP, the caller's own are marked: `mine` in `structuredContent`, `*` in the text) and each guest's display size in pixels (DISPLAY: the VNC framebuffer's, which the VNC server announces over one held connection (desktop-size notices, no polling) and which is reported once it has held for a second, `-` until then)
* OPTIONS: `[--ephemeral | --save CHILDLAYER | --clone SIBLINGLAYER | --continue] [--memory MB] [--cpus N] [--user USERNAME] [--password PW] [--accept-license] [--disk GB] [--install RECIPE | --provision RECIPE] [--tweak TWEAK]... [--by NAME]`
* `--by NAME` records who started the VM (1 to 64 printable ASCII characters, no spaces) in `info.json` and its `deceased/` record, which `ps` and `ps --deceased` show as BY; a label, not a permission: any caller may use or stop any VM; default `window` for `run`, `cli` for `start` on the command line, and `mcp:CLIENT:PID` over MCP (CLIENT: the client's name from the request's `_meta` or `initialize`, else `mcp`, other characters as `-`, cut to fit; PID: the server's process), which over MCP is also whose VMs `ps` marks as the caller's
* `start` and `run` take a stored image or a layer (see [layers](#layers)); `start` runs `terrarium __serve ID IMAGE|- RECIPE|- MEMORY|- CPUS|- p:PASSWORD|- accept|- USERNAME|- TWEAKS|- DISK|- LAYER|- keep|- SAVE|- BY` (TWEAKS: the tweaks' full names, comma-separated; LAYER: the layer's path; `keep`: `--clone` or `--continue`; SAVE: the layer to save when the VM stops; BY: as `--by`) in its own session and returns when the VM is running; a guest that stops by itself within two seconds of that (firmware found nothing to boot) is an error, "the guest stopped itself", and the owner notes it; `run` serves in its own process
* the save options say what becomes of the VM's work, and are alternatives: `--ephemeral` discards it when the VM stops (unless a `commit` saved it); `--save CHILDLAYER` saves it as the new layer CHILDLAYER, a child of what the VM started from (an install: a root layer); `--clone SIBLINGLAYER` saves the starting layer's changes and the VM's as the sibling SIBLINGLAYER; `--continue` saves back to the starting layer, replacing it; `--clone` and `--continue` take a layer only; `--save-sibling` and `--save-over` are command-line aliases of them (not MCP parameters)
* `start` needs one of the four, since nobody is there to ask; `run` may leave them out, and its closing sheet asks; a save is scheduled as `commit LAYER --on-stop` as soon as the VM runs (`run`: at once, before an install starts), checked first, so a bad target fails before anything starts
* `--memory` (MiB) and `--cpus` must be whole numbers within what Virtualization allows on the Mac, checked before anything starts
* `--tweak TWEAK` (repeatable) runs [tweaks](#tweaks) in the guest once its helper answers, as `tweak` does; `start` returns only after they succeed; a layer takes it; with `--install`, only `macos` (and then `--user`), where they run once the helper is installed (a failed helper install fails them), `ps` shows `tweaking TWEAK`, `start` has already returned, and a failure stops the VM, so an on-stop commit saves nothing
* `start` and `run` refuse an installer image without its `--install`, saying which recipe it needs and that `--accept-license` is the caller's agreement to the vendor's license
* `--accept-license` is the caller's agreement to the guest vendor's license, given per install and never implied: only with `--install windows` or `macos`, and `start` says which license it accepted; without it Windows stops at Microsoft's license page and macOS at Setup Assistant (the helper is then not installed) for the caller to finish (`shot`, `click`), and the rest is automatic
* `--user USERNAME` names the account an install creates: only with `--install windows` (always created; default `terra`) or `macos` (created only with it, and then only with `--accept-license`, since first-boot provisioning skips Setup Assistant, where the license is agreed to; `--accept-license` alone is refused); 1 to 20 ASCII letters, digits, `_`, or `-`, starting with a letter or `_`, and not `root`, `administrator`, `guest`, `system`, or `defaultaccount`
* `--disk GB` sizes the new guest's disk: only with `--install`, a whole number from the recipe's default (4 for `alpine`, 40 for `macos` and `windows`) to 1000, recorded as the layer's `diskGB`, a sparse file that takes only what the guest writes; resizing an existing disk is not supported
* `--password` sets the guest account's password when installing or provisioning: only with `--install` (for `macos`, with `--user`) or `--provision nocloud` (US keyboard characters, which are typed), never empty; `/bin/ps` shows it, except that `run --password -` reads it from standard input (a prompt without echo on a terminal) and never outputs it; `start` refuses `-`, since `__serve` takes the password as an argument

### observe and control

Each takes the VM first, as `VM`: its ID or a unique prefix of it. There is no default, so a call always names its VM.

* `shot VM` → PNG; coordinates in other verbs are relative to it; read from the private `_VZVNCServer` (loopback, no security) by an in-process RFB client
* a glide steps about 60 times a second, eased in and out (smoothstep), from the pointer's last position the owner sent (the screen's center before any), and a recording sees each step
* `shot` waits until a second has passed since the last `click`, `move`, `type`, or `key` finished; it then nudges the pointer 1 px and back (no click), then returns the first frame equal to the one before it and not black (at most 8 retries, 0.3 s apart), each sampled on its own connection
* a guest's pointer is in the VNC framebuffer only when the guest draws it there (Windows); the VNC server neither composites a hardware cursor (macOS, and likely Linux) nor sends its shape
* `record VM PATH [--fps N] [--max-seconds N] [--clicks] [--crop X,Y,W,H]` → `recording to PATH` once the first frame is in; `record VM --stop` → `PATH: SECONDS s, N frames`; one recording per VM, also ended (and noted in `serve.log`) at `--max-seconds` (default 600), when the display goes away (a Windows reset), and when the VM stops, before it exits
* PATH: a `.mov` or `.mp4` file that does not exist, in a directory that does, resolved by the caller; `--fps` 1 to 30 (default 10); `--max-seconds` 1 to 86400; `--crop` four whole numbers, each side at least 16, within the first frame
* the owner holds one VNC connection for it, off the main queue, requesting incremental updates of the whole screen (raw BGRX); a frame is appended, stamped with the time since the start, only when the screen or an overlay changed, at most `--fps` a second; encoded in-process by `AVAssetWriter` (its pixel-buffer receiver), H.264, no sound
* the output is the first frame's size (or the crop's), rounded down to even sides; a later size is fitted into it, keeping its aspect ratio, with black bars
* overlays, in guest pixels at 1x (2x on a display over 2000 pixels across): the pointer, for a guest other than Windows, as a black arrow edged in white at the last position the owner sent; and with `--clicks`, a mark at each press the owner sends (a dot shrinking from 9 px and a 3 px ring growing from 6 to 26 px, eased out) and at the release of a drag (the ring alone), 0.35 s long and fading, amber `#e0a526` for the left button, blue `#5b8fd6` for the right, and purple `#9b74d1` for the middle (the diagrams' hues, brightened), over a translucent dark edge; a frame follows a mark's end, so its last faded frame is not held; pointer moves and clicks in a `run` window are not seen
* `logs VM` → the VM's console log
* `click VM X,Y [--button B] [--drag-to X,Y] [--scroll DX,DY] [--duration MS]` → positive scroll amounts go down and right; `--duration` (1 to 10000) glides the pointer to X,Y over that long before the click or, with `--drag-to`, makes the drag take that long, and does not apply to `--scroll`
* `move VM X,Y [--duration MS]` → moves the pointer without a click, so it can be parked out of a `shot`; `--duration` (1 to 10000) glides it there from where it was
* `resize VM WxH` → asks the guest for a display of that size in pixels (each side 64 to 16384), as the window's Match Guest to Window does; a guest that ignores the request keeps its size
* `type VM TEXT [--interval MS]` → US keyboard ASCII, newline as Return; `--interval` (1 to 1000) pauses that long after each character but the last, and the client waits as long as the typing takes
* `key VM [CHORD+]KEY` → modifiers `ctrl`, `shift`, `alt`, and `win` (also as the key alone) are mapped to the keysyms the VNC server's keyboard expects (`alt` → `Meta_L`, `win` → `Alt_L`)
* `exec VM COMMAND [ARGS...] [--timeout SECONDS]` → runs without a shell and with empty stdin, streams stdout and stderr, and exits with the command's status (128 plus the signal number if it was killed; a code outside 0 to 255 exits 1); it ends when the command exits, even while something it started holds its output; a CLI or VM that goes away kills the command and all it started (its process group; a job object on Windows); `--timeout` does so after that long, from when the call connects, with a line on stderr and status 124 (no limit by default)
* `tweak VM TWEAK` → runs [tweak](#tweaks) TWEAK in the guest, waiting for the helper to answer; streams its stdout and stderr and exits with its status (124 after a line on stderr when it outlasts its timeout; 2 for an unknown name or one for another OS)
* `wait VM [--down | --reboot] [--timeout SECONDS]` → returns `ready` once the VM's state is `running` (booting and tweaks done) and its helper answers a hello, polling every 2 s; fails at the timeout (default 600) or when the VM stops; with `--down` it returns `down` once the VM has stopped (its files gone, so a scheduled commit is saved) or its helper, having answered, no longer does, polling every 0.5 s, and fails at the timeout while the guest is up (a guest that restarts between two polls is missed); with `--reboot` it returns `rebooted` once the helper answers with an instance ID other than the one the owner holds as the last that `wait` found (none held: the first this call sees), then holds the new one, polling every 0.5 s; a helper that sends no instance ID is an error
* `put VM HOST_PATH GUEST_PATH` → copies a file, or a directory's regular files (under GUEST_PATH, by relative path; empty directories, symlinks, and other kinds are skipped and counted) into the guest, making missing directories; each file arrives whole or not at all, replacing any there, with its mode on Linux and macOS; GUEST_PATH is absolute (on Windows, with a drive letter); prints the file and byte counts
* `get VM GUEST_PATH HOST_PATH` → copies one file out, whole or not at all; HOST_PATH is the file to write, or a directory to put it in under its own name
* `put` waits for the owner's `ok` before sending its data frames, which the owner passes on to the helper; `get` is the reverse
* `clipboard VM get` → the guest's clipboard text; `clipboard VM set TEXT|-` (`-`: standard input, on the command line only) → sets it
* clipboard text is UTF-8 with LF, at most 1 MiB (larger is refused, not cut); the helper converts at the guest's end (the Windows one to and from CRLF)
* `clipboard set` falls back to typing the text as `type` does when the guest has no clipboard (no helper yet, or the helper answers no clipboard, as at a console), and says so; the text must then be US ASCII of at most 4 KiB, else it is refused before anything is typed; `clipboard get` has no fallback
* the VNC client runs off the main queue, which the VNC server shares with the VM

## run window

* the guest keeps its size and the window is a view of it at a scale, in device pixels per guest pixel (100% is pixel-perfect); resizing the window changes the scale
* scale snaps to 25, 50, 75, 100, 125, 150, 200, or 300 percent (the crisp ones are the whole ratios: 25, 50, 200, 300)
* the window starts at 1280x800 points, the step nearest the screen's pixel density (200% on a Retina screen), and keeps its scale in device pixels when it moves to a screen of another density
* the window is always held to the guest's aspect ratio (no bars), keeps its scale when the guest changes size (or the largest step that still fits the screen, as when it starts), and takes the new shape once it has held for ten seconds in the first two minutes after the VM starts, one second after that
* closing the window (Stop VM and Close Window, Command-W; or Stop VM and Quit, Command-Q; or quitting from the Dock or at logout) stops the VM, and AppKit's termination is always cancelled, so a logout must be repeated; `--save`, `--clone`, or `--continue` schedules `commit LAYER --on-stop` at the start, checked first
* when the guest has written to its disk since the VM started or was last committed (the VM's delta's modification time or size differs) and no commit is scheduled, closing asks first, in a sheet: Commit… (then stops once the commit is saved), Stop Without Committing (Command-D), or Cancel
* the title shows the VM's state and a pending commit
* menus:
  * Terrarium: About, Hide, Hide Others, Show All, Stop VM and Quit
  * File: Commit… and Commit When VM Stops… (`commit`, to a layer: the save panel starts in the layer store and adds `.layer`), Screenshot…, Reveal VM Folder, Copy VM ID, Stop VM and Close Window
  * Edit: Paste to Guest (Command-V) and Copy from Guest (Command-C), which are `clipboard set` of the host's pasteboard text and `clipboard get` into it, disabled unless the VM is running; failures show in a sheet
  * Edit > Share Clipboard: off by default, kept in the host's user defaults for all VMs; when the window becomes key it sends the host's pasteboard text if that changed since the last sync, and when it resigns key it fetches the guest's and sets the host's if that differs; no type fallback, and failures go to the console log
  * VM: Pause/Resume, Send Key (Escape, then the guest OS's own items, each titled by its effect and chord, *e.g.*, "Security Screen (Ctrl+Alt+Delete)": Windows: Ctrl+Alt+Delete, Windows Key, Win+R, Win+D, Ctrl+Shift+Esc, Alt+Tab, Alt+F4, Shift+F10; macOS: Cmd+Space, Cmd+Tab, Cmd+Q, Cmd+Option+Esc, Ctrl+Cmd+Q, Ctrl+Up; Linux: Log Out (Ctrl+Alt+Delete), a Switch Console submenu of Ctrl+Alt+F1 to F6, and a Desktop submenu of Super, Super+A, Alt+F2, Ctrl+Alt+T, Alt+Tab, Alt+F4, and Shift+Ctrl+Alt+R), Capture System Keys (off: the host keeps its shortcuts; on: every menu's key equivalents are cleared, since the guest gets every key)
  * View: Actual Size, Zoom In (also bound to Command-=), Zoom Out, Scale (the steps), Match Guest to Window; those that do not fit the screen are off
  * View > Match Guest to Window: one request for a guest display of the window's pixels (2560x1600 for a 1280x800-point window on a Retina Mac); a guest that follows keeps the window's size, so the scale becomes 100%; one that ignores it changes nothing
  * Window: Minimize, Console Log (off for macOS, which has no console)

## VM process

* serves the other verbs over a local socket (`vms/<id>/sock` in the support directory; one JSON line per request, `{"verb": ...}` for `stop`, `commit`, `info`, `logs`, `shot`, `record`, `click`, `move`, `resize`, `type`, `key`, `exec`, `tweak`, `clipboard`, `helper`, `put`, and `get`; the reply is `ok` or `error: MESSAGE`, a newline, and the payload); connections are accepted and read off the main queue, which the VM shares, and only the handling runs on it
* state (the delta, `nvram`, `console.log`, `info.json`) lives in `vms/<id>/` (mode 0700), removed when the VM stops, and by `terrarium ps` and `terrarium stop` when its process is gone; `console.log` is appended to across a Windows guest's restarts
* a record of how each VM ended (status, and a reason such as `stopped by stop`, `the guest stopped itself`, or `its process is gone`, with where a scheduled commit saved it) is kept in `deceased/<id>.json`, the last 20, and `ps --deceased` lists them, newest first
* a password the owner generates is printed once by `start`, kept in `vms/<id>/<guest>-password` (0600; `alpine`, `macos`, or `windows`) until the VM stops, and is in `vms/<id>/serve.log`, the owner's output, meanwhile
* SIGTERM, SIGINT, and SIGHUP stop the VM as `stop` does; before the VM exists (building media), they remove `vms/<id>/` and exit
* boots any stored image as an EFI disk: generic platform, virtio block, 4 GiB and up to 4 CPUs by default, 1280x800 virtio graphics, USB keyboard and pointer, NAT, vsock, entropy, and a serial console log
* Windows guests need `--install windows`; a macOS restore image (an IPSW) needs `--install macos`, which boots Apple's platform instead
* runtime host-guest files: VZVirtioFileSystemDeviceConfiguration

## mcp

* `terrarium mcp` serves the verbs except `run` as MCP tools, revision 2026-07-28 (collected in [README.md](docs/specifications/README.md)), on stdin and stdout: one JSON-RPC message per line, nothing else on stdout, logs on stderr, exits when stdin closes
* tool and argument names are the verbs' and parameters' own, plus `vm` and, for `exec`, `args` (the arguments after COMMAND); flags are booleans, `--memory` and `--cpus` integers
* every request needs `_meta` with the protocol version and client capabilities, else error -32602; an unsupported version is -32022 with `supported` and `requested`; `server/discover`, `tools/list` (in the verbs' order), and `tools/call` are served, the first two with `ttlMs` and `cacheScope`; results carry `resultType` and the server's `serverInfo`
* a legacy `initialize` is accepted too; after it, requests need no `_meta` and results carry no `resultType`
* a rejected argument or a failed command is a tool error (`isError`); an unknown tool is -32602
* `shot` returns an image block (base64 PNG); `exec` returns stdout, stderr, and the exit status as text and `structuredContent`, each stream cut at 1 MiB, and a non-zero status is an error; `start` returns the ID, the owner's notes, and, when a recipe generated an account's password, `user` and `password` in `structuredContent`, with `notifications/progress` when the request has a progress token
* calls run concurrently, each on a thread of its own; `notifications/cancelled` stops an `exec` (even one not yet connected), killing the guest's process, and gets no response; other tools are not cancellable and still answer; a request whose id is already in flight is -32600
* the server's instructions say that a VM the user runs in a window (`run`, which is not a tool) is in `ps` and can be observed and driven alongside the user, who is asked before it is stopped or committed, and suggest, as a courtesy and not a rule, that a client prefer the VMs it started (marked as its own in `ps`) and pass them as `vm`, check before it stops or removes what it did not start, and save what it makes as a new layer (`save` a child, or `clone` a sibling) instead of replacing one, since VMs, images, and layers are shared with other sessions
* VMs outlive the server; it reaps the owner processes it starts

## helper

* listens on vsock port 4242 for `terrarium` requests, one per connection, each on its own thread; on Linux and macOS the commands it runs do not inherit its sockets
* a frame is a kind byte, a big-endian u32 length (at most 16 MiB), and the payload
* host → helper: `0x00` hello; `0x01` exec, JSON `{"argv": [...]}`; `0x02` clipboard get; `0x03` clipboard set (UTF-8 payload; answered by an exit frame of 0); `0x04` put, JSON `{"path": ..., "mode": ...}`, then `0x05` data frames of at most 1 MiB and an empty one to end (answered by an exit frame of 0); `0x06` get, JSON `{"path": ...}`
* helper → host: `0x00` hello (`terrarium-helper 1 <os> <instance>`, the instance being 16 hex digits chosen at each start of the helper); `0x10` stdout; `0x11` stderr; `0x13` clipboard text (UTF-8); `0x05` data (a get's file, then an exit frame of 0); `0x12` exit (big-endian i32: the exit code, all 32 bits on Windows, or the negated signal, 1 to 64); `0x1f` error (ends the exchange; also answers a frame over the limit)
* the Linux, macOS, and Windows helpers speak it; the Windows one reaches the host through the `viosock` Winsock provider, whose address family it asks the driver for
* the clipboard is the session's: `pbpaste` and `pbcopy` on macOS, the Win32 clipboard on Windows, and `wl-paste`/`wl-copy` or `xclip` (display `:0`, no `XAUTHORITY`) on Linux when a graphical session and the tool exist, which a root service rarely reaches; otherwise `0x1f` with "no clipboard"
* until a recipe installs it, a guest must be given the helper by hand

## image store

* store: `images/` in the support directory (see [modules](#modules))
* IMAGE is `<name>-<hash>`, a name without the hash that only one image has, or a unique prefix of the full name; an empty IMAGE or VM matches nothing
* `pull` writes `*.partial.<pid>.<n>` (`n` counts the process's pulls, so concurrent ones keep apart), then renames it `<name>-<hash>.img`, the hash (16 hex digits) covering the source bytes and the converter's recipe version, keeping an existing file of that name; a local PATH needing no conversion is cloned with `clonefile(2)` when on the store's APFS volume, else copied; PATH must be a file, not a bundle
* `pull` identifies compression by magic bytes and decompresses `.xz` with the `Compression` framework's `COMPRESSION_LZMA` and `.gz` with `gunzip`, writing zero blocks as holes
* `pull` extracts the one file of a tar archive (magic `ustar`; an archive of several files is refused) and writes zero blocks as holes
* `pull` converts with `diskutil image create from` only when `diskutil image info` reports a format other than RAW; raw disks, ISOs, and macOS restore images (zip files) are stored as is
* `pull` converts a qcow2 image (magic `QFI\xFB`; version 2 or 3, plain or zlib-compressed clusters, no backing file, encryption, or extended features, tables within the file, a disk of at most 64 TiB; else refused) to RAW in-process; `start` and `run` refuse a stored qcow2 image
* images are stored read-only
* startup removes `*.partial.<pid>` and `*.partial.<pid>.<n>` files whose process is gone
* each `diskutil image attach` is recorded in `attached/` in the support directory (device, image, first-partition GUID, process); a disk attached blank is recorded again once partitioned; an eject that fails (after a forced unmount) keeps its record; startup ejects recorded images whose process is gone and whose GUID still matches, never others

## layers

One saved object, a layer, that descends from an image or another layer. Terms follow ancestry and name no direction: parent, child, ancestor, descendant, root. A VM's own writes are its **delta**.

* an **image** is read-only input in the [image store](#image-store): **live** (the root of a chain) or **installer** (an ISO or IPSW that `--install` consumes and never boots)
* a **layer** is everything saved, a bundle `NAME.layer/`:
  * `manifest.json`: `version` 2, `guest` (`windows`, `macos`, or `linux`), `diskGB`, `installer` (the image's name, as provenance), `id` (16 hex digits chosen at every `commit`), and `chain` (the ancestors' ids, root first, an image by its name)
  * `chain/`: the ancestors' files, `<n>-<id>.asif` (an image: `<n>-<name>.img`), root first
  * `delta.asif`: the layer's own changes from its parent
  * for macOS, the auxiliary storage, hardware model, and machine identifier
* a **root layer** has an empty chain: what `--install` leaves, over a blank sparse disk of `diskGB` that terrarium regenerates; any other layer has a parent, an image or a layer
* the files in `chain/` are `clonefile(2)` clones (off the store's APFS volume, `copyfile(3)` copies that keep holes), never hard links: moving or deleting a parent leaves its children whole, and its space is freed with the last clone
* a VM opens `chain/` files read-only and writes only its own delta, in `vms/<id>/`, discarded on `stop` unless saved with `commit`; what it started from is never written
* DiskImageKit refuses a layer whose parent UUID is not the layer below it; a layer on a raw disk has none, and the manifest's ids (new at every `commit`) with the rule that `chain/` files are never written keep a child on the contents it was made from
* a directory without a manifest is not a layer; a layer with another `version` was saved by an earlier terrarium and is refused; a missing chain file is "layer NAME is damaged"

### store

* `layers/` in the support directory (`~/Library/Application Support/terrarium/layers/`), made when first needed; a layer in it is `layers/NAME.layer`
* LAYER names a layer as IMAGE names an image: NAME (without `.layer`) is found in the store; an argument with a `/`, a leading `~`, or ending `.layer` is that path, so a layer can live anywhere and be moved
* `commit` saves to `layers/NAME.layer` when LAYER is a name, else to the path (`.layer` added)
* a name that is both an image's and a layer's is refused, saying which two; `ps` names what each VM started from, a layer by its name (in the store) or path

### saving: save, clone, continue

* **save**: `start IMAGE|LAYER --save CHILDLAYER`, or `commit VM --save CHILDLAYER`, saves the delta as a child: its chain is the parent's chain and the parent
* **clone**: `start LAYER --clone SIBLINGLAYER`, or `commit VM --clone SIBLINGLAYER` on a VM started that way; the VM's delta starts as a clone of the layer's `delta.asif`, and the save is a sibling of the starting layer (same parent, keeping its changes)
* **continue**: `start LAYER --continue` is `--clone` saving back to the starting layer, which a save replaces; the chain keeps its length however many sessions follow; a save of a VM that has written nothing since it started or was last saved (its delta's modification time and size are as then, read after the flush) replaces nothing, so the layer keeps its `id`: `commit --continue` says `unchanged` after the path, and a stop notes it; the other saves are made as asked, and a stop notes that the VM wrote nothing
* all three boot the same disk contents; they differ only in what is saved, a child, a sibling, or the layer itself
* a layer takes no `--install`, `--provision`, `--disk`, `--user`, `--accept-license`, or `--password`
* `--install` takes an installer image only; what it leaves, saved with `--save` or `commit`, is a root layer; a live image with `--provision` (or none) starts a chain at that image
* before a `commit` pauses the VM, and before a stop that has a save scheduled, the owner asks the guest through the helper to write its disk (`sync`; on Windows, `Write-VolumeCache -DriveLetter C`), for up to 30 s; a guest whose helper does not answer within 5 s (a console, an installer) is saved as it is, with a note; an unsaved stop is not delayed
* `commit` pauses the VM (unless it is paused), clones the files off the main queue into a bundle beside the target, and resumes, so the copy holds what the guest has flushed; a stop asked for meanwhile waits for it; a failed save leaves no target; `--on-stop` clones after the VM stops
* `commit` refuses an existing target and a missing directory, except that a VM started with `--clone` or `--continue` may save to the layer it started from: the bundle is swapped in (`renamex_np` with `RENAME_SWAP`) and the old one removed, refused if the layer's `id` is no longer the one started from, or if the layer is gone (moved or removed), which is not recreated; layers made from it are unaffected; the layer itself is never written, so a VM or Mac that dies leaves it as the last save made it
* an on-stop commit that fails, or that would save a VM that stopped with an error or an install that did not finish, saves nothing and moves the VM's files (including any password file) to `unsaved/<id>/` in the support directory
* startup removes `.NAME.layer.partial.<pid>` bundles whose process is gone

### concurrent use

* any number of VMs may start from one layer, each writing only its own delta
* the VM that will save a layer reserves its name for its life: an advisory `flock(2)` on `.NAME.layer.lock` beside it, taken by the VM's process, so a second VM aiming at the same name (`--save`, `--clone`, or `--continue`) or a `squash` is refused at start, and a crash leaves nothing stale; `squash` reserves NEWLAYER the same way while it runs; a `commit` to a name chosen late is not reserved
* a VM started from a layer first clones the whole bundle into `vms/<id>/pinned/layer` in one `clonefile(2)` call and reads its manifest, chain, delta, and identity files from the clone, so a `--continue` VM replacing the layer meanwhile changes nothing the VM reads, commits, or reopens after a restart; a layer that cannot be cloned (another volume) is used in place; `pinned/` goes with the VM's files and is not kept in `unsaved/`
* starting a layer whose chain and delta are more than 32 files deep notes that `squash` would make it read faster; there is no limit

### squash

* `squash LAYER NEWLAYER [--onto ANCESTOR]` needs no VM; NEWLAYER is named as `commit` names a target, must not exist, and its directory must
* ANCESTOR: an id or image name in LAYER's chain, a stored image, or a layer whose `id` is in it; anything else is a usage error; default: the image at the chain's root, or nothing over a blank disk
* NEWLAYER's manifest is LAYER's with a new `id` and the chain up to ANCESTOR; its `chain/` holds clones of those files, it keeps LAYER's identity files, and its delta is made as follows
* in a bundle `.NEWLAYER.layer.partial.<pid>` beside the target, it attaches with `diskutil image attach --nobrowse --noMount`, each recorded in `attached/`: A, the base (the root image, or a blank disk of `diskGB`) with LAYER's chain and delta as `--shadow`s, `--readOnly`; and B, the base with the new bundle's chain files and a new `delta.asif` as `--shadow`s, which `diskutil` makes as an ASIF child of the file below it
* it reads both raw devices in 8 MiB strides and, for each 4 KiB block where A differs, writes A's block into B, or, where A's block is zeros, unmaps it in B (`DKIOCUNMAP`, which masks what is below; a refused unmap means writing zeros from then on); then it reads both again and fails if they differ anywhere; then ejects both and renames the bundle into place
* it reads LAYER's files and never writes them; a failure ejects what it attached and removes the bundle

## tweaks

* OS-specific changes to a guest (*e.g.*, settings): a script per tweak, run in the guest through the helper
* `tweak TWEAK` runs one in a running guest; `--tweak TWEAK` on `start` or `run` (repeatable) runs them, in the order given, once the helper answers; both use the same code
* `TWEAK` is `<os>/<name>` (`windows/edge-quiet`) or a bare `<name>`, which is the guest's own when its OS has one (`no-sleep` on a macOS guest) and otherwise must belong to only one OS
* the files are `core/tweaks/<os>/<name>.<ext>`, embedded by `build.zig` as `__TERRARIUM` sections like the recipes' scripts: `.ps1` for Windows, `.sh` for Linux and macOS
* a tweak's header is its leading comment lines (`#`, after any shebang): the first is what it does, and later `key: value` lines are settings, of which `timeout: SECONDS` is the first (default 10); unknown keys are ignored, so new ones can be added
* a tweak declares its OS by its directory; one that does not match the guest's, or an unknown name, is a usage error, found before a VM starts
* the helper runs it as `powershell -NoProfile -NonInteractive -EncodedCommand` (progress output off) or `sh -c`, with the privileges `exec` has; no stdin
* a tweak fails when it exits non-zero, cannot run, or outlasts its timeout (it and what it started are killed); a failure propagates as an exiting error: `tweak` exits with its status (124 for a timeout), and `start` or `run` stops the VM and exits 1, saying which tweak failed and showing its output
* `ps` shows state `tweaking` from the VM's start until its helper answers (for a macOS install, through the helper's installation), then `tweaking TWEAK` while one runs, then `running`; `start` returns when all have succeeded
* `ps` shows state `booting` from the start of a guest that terrarium gave a helper (a `--provision` recipe or a layer, without `--tweak`) until the helper answers, then `running`; `start` does not wait for it, and a helper silent after ten minutes is noted and the state becomes `running`
* a tweak must be safe to run again; a change persists only if the layer is committed
* only embedded tweaks, never paths
* each tweak's description and timeout are in the catalog, [docs/tweaks.md](docs/tweaks.md), which is their source of truth

## recipes

### shared

* boot-time guest setup, built on the host before the guest runs; independent of disk layout
* `--install RECIPE` (`alpine`, `macos`, `windows`) installs the installer IMAGE onto a new guest, and `--provision RECIPE` (`alpine`, `cloud-init`, `combustion`, `nocloud`) readies a live IMAGE's guest to be driven; they are alternatives, and a layer takes neither; without either, the guest is untouched
* the caller picks the recipe for the image; `pull` never runs one
* `alpine` is one name under each flag, two recipes
* `--install` masters a persistent guest: `start` the installer image with it, then `commit`
* the VM's process builds the media in `vms/<id>/` and attaches it read-only, as virtio block devices after the boot disk
* a recipe installs the helper and its launch hook
* Linux and Windows recipes are delivered on labeled FAT or exFAT block media, not VirtioFS: `diskutil image create blank` (one volume) or `partitionDisk` (several), then `dot_clean`, `mdutil -i off`, and `fsck_msdos` or `fsck_exfat`

### `--install macos`

* installs the restore image onto a blank disk (40 GB by default) with `VZMacOSInstaller` (8 GiB by default), in the VM's process before the guest starts; `start` returns at once (state `installing N%` in `terrarium ps`)
* then boots it once with first-boot `VZMacGuestProvisioningOptions` (account `--user`, a random password or `--password`, auto-login, Remote Login; with `--user` and `--accept-license`)
* installs, over SSH at the guest's NAT address (from `/var/db/dhcpd_leases`, by MAC address; the password reaches `ssh` through `SSH_ASKPASS` and `sudo -S`): the helper, `/Library/LaunchAgents/dev.terrarium.helper.plist` (a LaunchAgent, so the helper runs as the account, in its session), and `/etc/sudoers.d/terrarium` (the account gets passwordless `sudo`)
* first boot only; the guest is saved as a root layer

### `--provision alpine`

* `terrarium.apkovl.tar.gz` on a FAT volume, applied every boot: the helper, an OpenRC service in the default runlevel (loads `vmw_vsock_virtio_transport`), and `etc/.default_boot_services` so Alpine still adds its own; files owned by root

### `--install alpine`

* the ISO boots first (read-only), then the recipe's volume, then a blank 4 GB disk (sparse, in the VM's directory) with the VM's delta on top
* the apkovl's `local.d` hook runs `ERASE_DISKS=DISK setup-alpine -e -f` on the largest virtio disk from an answer file (US keymap, hostname `terrarium`, DHCP on `eth0`, UTC, `sys` mode, packages from the network's first mirror)
* then it removes the recipe's own files (the hook and `etc/terrarium`, which `setup-alpine` copies) from the new root, puts the helper, an OpenRC service, and the root password (random, or `--password`; printed once by `start`) into it, checks that root has a password, prints `terrarium: Alpine is installed` on the console, and powers off; any failed step prints why and powers off too
* save it with `commit --on-stop` first as a root layer of kind `linux`, which boots from its own disk; it is saved only when `console.log` holds the success line

### `--provision cloud-init`

* NoCloud FAT volume labeled `CIDATA`: `user-data` writes the helper (base64) and a systemd unit and starts it, and `meta-data` takes the VM's ID as the instance ID, so every `start` runs it
* on a guest without systemd (Alpine's cloud images), it installs an OpenRC service for the helper instead and starts it, and limits cloud-init to the `NoCloud` and `None` datasources, so a later boot without `CIDATA` does not wait on others

### `--provision nocloud`

* for an image with no cloud-init that asks its questions on the text console (Debian's `nocloud` images): a FAT volume labeled `TERRARIUM` holds the helper and `install.sh`, which installs the helper as a systemd unit and starts it
* answers the first-boot wizard over VNC as its questions appear: the screen is read every 2 s (Vision's text recognition) and each answer typed once its prompt shows (matched ignoring case and spacing, a misread character allowed in a phrase of eight or more), in order: systemd's "Press any key" (skipped on an image that starts at the timezone, as Debian 14's does), the timezone (skipped), root's password (`--password`, else random and printed once by `start`, kept in `vms/<id>/nocloud-password` until the VM stops) and its confirmation, then the login and the command that mounts the volume and runs `install.sh`; seven minutes without the next prompt end the dialogue, with a note
* the helper answers about 100 s after the start, and a committed layer has the wizard's answers, the password, and the unit, so a later boot needs no `--provision`

### `--provision combustion`

* for openSUSE's Minimal-VM, MicroOS, and Leap Micro images, which configure themselves at first boot with Combustion, not cloud-init: a FAT volume labeled `COMBUSTION` holds `combustion/script` and the helper beside it; Combustion copies that directory and runs the script from inside it, which installs the helper and a systemd unit for it
* runs only at the image's first boot, so a committed layer (or any layer made from it) has the helper and later boots need no `--provision`

### `--install windows`

* media: installer media (GPT disk: FAT32 boot tree, exFAT `install.wim`; built once per image) and a writable FAT boot disk (EFI shim, virtio-win drivers, install script, answer file, helper), both on USB
* the shim gives the firmware GOP a linear framebuffer and chainloads the installer, and puts back what it changed if the loaded image returns
* spaces (3 to 15 s), Shift+F10 (62 s), and `C:\install.cmd` (70 s) typed over VNC start the install script, which applies the Professional edition (found from the WIM's XML) to the boot disk, adds the drivers, copies the shim to the installed ESP, and shuts down
* `SetupComplete.cmd` makes the helper an at-logon task for the account at the highest run level, so it runs in the auto-logon session (the clipboard needs one) with the account's elevated rights, and is reachable once that logon completes; the installed system carries its own shim and is saved as a root layer
* guests boot from NVMe over a blank base disk (40 GB by default; sparse, in the VM's directory), not the image; they get 8 GiB by default and the performance monitoring unit (private `_setPerformanceMonitoringUnitEmulationEnabled:`, checked before use)
* the answer file makes a local administrator (`--user`, default `terra`) with auto-logon and a random password (or the `--password` given; markup characters are escaped), printed once by `start` and kept in `vms/<id>/windows-password` until the VM stops when random
* the installer's shutdown stops the VM, so save the install with `commit --on-stop` first; the install script stops at the first failed step and writes `install.ok` to the boot disk only when every step succeeded, and once the VM stops, terrarium reads the boot disk read-only and, without the marker, shows the end of `install.log` and treats the install as not finished
* the virtio-win drivers (`viogpudo`, `NetKVM`, `viosock`; pinned URL and SHA-256) are downloaded once into `cache/`, as is the installer media; startup removes stale `*.partial.<pid>` files there too, and the `blank-disk-*` files of earlier versions
* a guest's reset stops the VM with an error; `start` and `run` restart it on the same disk and media, up to ten times, after stopping the VNC server
* a guest gets a new EFI variable store at every boot

## references and specifications

see [README.md](docs/specifications/README.md)
