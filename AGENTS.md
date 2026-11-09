# terrarium: a stdio MCP tool and CLI that drives macOS, Linux, and Windows guests from a Mac

* host `terrarium` in Swift (`core/`, `ui/`, `cli/`), on Virtualization framework, in three modules (see [modules](#modules)); guest code in Zig (`guest/`); checks in `tests/` (`zig build test`: the helper's frames, unit checks of the core's helpers in `tests/unit/`, MCP, and `pull`, in a temporary support directory; `live*.py` by hand); maintenance scripts in `tools/`, which generates [docs/distros.md](docs/distros.md) (see its [README](tools/README.md))
* guest `terrarium-helper` in Zig 0.17+, static, embedded in `terrarium`
* `zig build` builds the helpers (aarch64 macOS, Linux musl, and Windows), links them into `terrarium` (`__TERRARIUM` sections `macos`, `linux`, `windows`), the Windows shim and its guest scripts (`winfb`, `win-*`), embeds `cli/Info.plist` (`__TEXT,__info_plist`, so the menu bar says Terrarium), and signs it with the `com.apple.security.virtualization` entitlement
* host: macOS 27+, aarch64; guests: macOS, Windows, Fedora, and Alpine (aarch64); see [docs/windows.md](docs/windows.md), [docs/macos.md](docs/macos.md), and the recipes' findings in [core/recipes](core/recipes/)
* external programs: any stock macOS program (never Homebrew or other installs), e.g. `diskutil`, `fsck_msdos`, `fsck_exfat`, `dot_clean`, `mdutil`, `codesign`, `gunzip`, `tar`, `rsync`, `ssh`, and `scp`; prefer `diskutil` over `hdiutil` and in-process APIs over programs; only to build, sign, and prepare images, never while a guest runs; read `--plist` output; no external libraries

## modules

* `TerrariumCore` (`core/`): everything but a front-end, with no AppKit: images, overlays, recipes, VM configuration and state, the owner process as a headless engine (`Owner`), the control socket, the guest link, the display client, and the verb table with the code behind each verb (`Backend`)
* `TerrariumUI` (`ui/`): the `run` window, its menus, scale, and console log, over AppKit; it attaches to an `Owner` through the `OwnerUI` protocol, which the core calls on the main queue
* `terrarium` (`cli/`, with `cli/mcp/`, `cli/Info.plist`, and the entitlements): the executable, a command line and an MCP server over the core's verbs, which hands `run` the window
* `core/` is layered, lowest first: `system`; `images`, `display`, and `guestlink`; `vm`; `recipes` and `tweaks`; `owner`; `verbs`; a directory uses only those below it, and those of one rank do not use each other (`tests/layers.py`)
* the core's public surface is what the front-ends use: the verb table, `Invocation` and `invocation(_:arguments:)`, `Backend`, `Launch.start`, `Remote.exec`, `Owner` and `OwnerUI`, `Paths`, and `CLIError`; a front-end sets `Backend.windowFactory` to give `run` a window
* the support directory, `Paths.support`: the front-end sets it once at startup, before anything else in the core; the core reads no environment
* `terrarium` sets it from `$TERRARIUM_SUPPORT` when set (as the tests do), else `~/Library/Application Support/terrarium/`
* its children, each defined once in `Paths`: `images/`, `vms/`, `cache/`, `attached/`, and `unsaved/`

## verbs

Each verb is a CLI subcommand and an MCP tool of the same name and parameters, except `run` (CLI only).

### images

* `pull URL|PATH` → downloads (if URL), decompresses, converts, hashes, and stores the image → IMAGE (see [image store](#image-store))
* `images` → lists stored images, each by its name without the hash unless another image has the same name (then `<name>-<hash>`)
* `rmi IMAGE` → removes a stored image

### lifecycle

* `run [IMAGE|PATH.guest] [OPTIONS] [--commit-on-stop PATH]` → ID; CLI only; foreground, shows the VM's display in a [window](#run-window)
* `start [IMAGE|PATH.guest] [OPTIONS]` → ID; hidden; returns at once, a background `terrarium` process keeps the VM
* `commit ID PATH [--on-stop]` → saves the VM's overlay now, or when the VM stops → PATH' (see [overlays](#overlays))
* `stop ID` → returns once the VM has stopped and any scheduled commit is saved
* `ps` → running VMs, naming each image as `images` does, with each guest's display size in pixels (DISPLAY: the VNC framebuffer's, which the VNC server announces over one held connection (desktop-size notices, no polling) and which is reported once it has held for a second, `-` until then)
* OPTIONS: `[--memory MB] [--cpus N] [--user NAME] [--password PW] [--accept-license] [--disk GB] [--overlay PATH'] [--install RECIPE | --provision RECIPE] [--tweak NAME]...`
* `start` and `run` take a stored image or, if the argument ends in `.guest`, an installed guest (see [overlays](#overlays)), which takes `--overlay` too; `start` runs `terrarium __serve ID IMAGE|- RECIPE|- MEMORY|- CPUS|- p:PASSWORD|- accept|- USER|- TWEAKS|- DISK|- [OVERLAY|- [GUEST]]` (TWEAKS: the tweaks' full names, comma-separated) in its own session and returns when the VM is running; a guest that stops by itself within two seconds of that (firmware found nothing to boot) is an error, "the guest stopped itself", and the owner notes it; `run` serves in its own process
* `--memory` (MiB) and `--cpus` must be whole numbers within what Virtualization allows on the Mac, checked before anything starts
* `--tweak NAME` (repeatable) runs [tweaks](#tweaks) in the guest once its helper answers, as `tweak` does; `start` returns only after they succeed; a guest and `--overlay` take it; with `--install`, only `macos` (and then `--user`), where they run once the helper is installed (a failed helper install fails them), `ps` shows `tweaking NAME`, `start` has already returned, and a failure stops the VM, so an on-stop commit saves nothing
* `--accept-license` is the caller's agreement to the guest vendor's license, given per install and never implied: only with `--install windows` or `macos`, and `start` says which license it accepted; without it Windows stops at Microsoft's license page and macOS at Setup Assistant (the helper is then not installed) for the caller to finish (`shot`, `click`), and the rest is automatic
* `--user NAME` names the account an install creates: only with `--install windows` (always created; default `terra`) or `macos` (created only with it, and then only with `--accept-license`, since first-boot provisioning skips Setup Assistant, where the license is agreed to; `--accept-license` alone is refused); 1 to 20 ASCII letters, digits, `_`, or `-`, starting with a letter or `_`, and not `root`, `administrator`, `guest`, `system`, or `defaultaccount`
* `--disk GB` sizes the new guest's disk: only with `--install`, a whole number from the recipe's default (4 for `alpine`, 40 for `macos` and `windows`) to 1000, recorded as the guest's `diskGB`; resizing an existing disk is not supported
* `--password` sets the guest account's password when installing or provisioning: only with `--install` (for `macos`, with `--user`) or `--provision nocloud` (US keyboard characters, which are typed), never empty; `/bin/ps` shows it, except that `run --password -` reads it from standard input (a prompt without echo on a terminal) and never outputs it; `start` refuses `-`, since `__serve` takes the password as an argument

### observe and control

Each takes `--vm ID`, defaulting to the only running VM.

* `shot` → PNG; coordinates in other verbs are relative to it; read from the private `_VZVNCServer` (loopback, no security) by an in-process RFB client
* `shot` first nudges the pointer 1 px and back (no click), then returns the first frame equal to the one before it and not black (at most 8 retries, 0.3 s apart), each sampled on its own connection
* `logs` → the VM's console log
* `click X,Y [--button B] [--drag-to X,Y] [--scroll DX,DY]` → positive scroll amounts go down and right
* `type TEXT` → US keyboard ASCII, newline as Return
* `key [CHORD+]KEY` → modifiers `ctrl`, `shift`, `alt`, and `win` (also as the key alone) are mapped to the keysyms the VNC server's keyboard expects (`alt` → `Meta_L`, `win` → `Alt_L`)
* `exec COMMAND [ARGS...]` → runs without a shell and with empty stdin, streams stdout and stderr, and exits with the command's status (128 plus the signal number if it was killed; a code outside 0 to 255 exits 1); it ends when the command exits, even while something it started holds its output; a CLI or VM that goes away kills the command and all it started (its process group; a job object on Windows)
* `tweak NAME` → runs [tweak](#tweaks) NAME in the guest, waiting for the helper to answer; streams its stdout and stderr and exits with its status (124 after a line on stderr when it outlasts its timeout; 2 for an unknown name or one for another OS)
* `clipboard get` → the guest's clipboard text; `clipboard set TEXT|-` (`-`: standard input, on the command line only) → sets it
* clipboard text is UTF-8 with LF, at most 1 MiB (larger is refused, not cut); the helper converts at the guest's end (the Windows one to and from CRLF)
* `clipboard set` falls back to typing the text as `type` does when the guest has no clipboard (no helper yet, or the helper answers no clipboard, as at a console), and says so; the text must then be US ASCII of at most 4 KiB, else it is refused before anything is typed; `clipboard get` has no fallback
* the VNC client runs off the main queue, which the VNC server shares with the VM

## run window

* the guest keeps its size and the window is a view of it at a scale, in device pixels per guest pixel (100% is pixel-perfect); resizing the window changes the scale
* scale snaps to 25, 50, 75, 100, 125, 150, 200, or 300 percent (the crisp ones are the whole ratios: 25, 50, 200, 300)
* the window starts at 1280x800 points, the step nearest the screen's pixel density (200% on a Retina screen), and keeps its scale in device pixels when it moves to a screen of another density
* the window is always held to the guest's aspect ratio (no bars), keeps its scale when the guest changes size (or the largest step that still fits the screen, as when it starts), and takes the new shape once it has held for ten seconds in the first two minutes after the VM starts, one second after that
* closing the window (Stop VM and Close Window, Command-W; or Stop VM and Quit, Command-Q; or quitting from the Dock or at logout) stops the VM, and AppKit's termination is always cancelled, so a logout must be repeated; `--commit-on-stop PATH` schedules `commit PATH --on-stop` at the start, checked first
* when the guest has written to its disk since the VM started or was last committed (the overlay layer's modification time or size differs) and no commit is scheduled, closing asks first, in a sheet: Commit… (then stops once the commit is saved), Stop Without Committing (Command-D), or Cancel
* the title shows the VM's state and a pending commit
* menus:
  * Terrarium: About, Hide, Hide Others, Show All, Stop VM and Quit
  * File: Commit… and Commit When VM Stops… (`commit`, named for the kind it saves), Screenshot…, Reveal VM Folder, Copy VM ID, Stop VM and Close Window
  * Edit: Paste to Guest (Command-V) and Copy from Guest (Command-C), which are `clipboard set` of the host's pasteboard text and `clipboard get` into it, disabled unless the VM is running; failures show in a sheet
  * Edit > Share Clipboard: off by default, kept in the host's user defaults for all VMs; when the window becomes key it sends the host's pasteboard text if that changed since the last sync, and when it resigns key it fetches the guest's and sets the host's if that differs; no type fallback, and failures go to the console log
  * VM: Pause/Resume, Send Key (Escape, then the guest OS's own items, each titled by its effect and chord, *e.g.*, "Security Screen (Ctrl+Alt+Delete)": Windows: Ctrl+Alt+Delete, Windows Key, Win+R, Win+D, Ctrl+Shift+Esc, Alt+Tab, Alt+F4, Shift+F10; macOS: Cmd+Space, Cmd+Tab, Cmd+Q, Cmd+Option+Esc, Ctrl+Cmd+Q, Ctrl+Up; Linux: Log Out (Ctrl+Alt+Delete), a Switch Console submenu of Ctrl+Alt+F1 to F6, and a Desktop submenu of Super, Super+A, Alt+F2, Ctrl+Alt+T, Alt+Tab, Alt+F4, and Shift+Ctrl+Alt+R), Capture System Keys (off: the host keeps its shortcuts; on: every menu's key equivalents are cleared, since the guest gets every key)
  * View: Actual Size, Zoom In (also bound to Command-=), Zoom Out, Scale (the steps), Match Guest to Window; those that do not fit the screen are off
  * View > Match Guest to Window: one request for a guest display of the window's pixels (2560x1600 for a 1280x800-point window on a Retina Mac); a guest that follows keeps the window's size, so the scale becomes 100%; one that ignores it changes nothing
  * Window: Minimize, Console Log (off for macOS, which has no console)

## VM process

* serves the other verbs over a local socket (`vms/<id>/sock` in the support directory; one JSON line per request, `{"verb": ...}` for `stop`, `commit`, `info`, `logs`, `shot`, `click`, `type`, `key`, `exec`, and `tweak`; the reply is `ok` or `error: MESSAGE`, a newline, and the payload); connections are accepted and read off the main queue, which the VM shares, and only the handling runs on it
* state (overlay, `nvram`, `console.log`, `info.json`) lives in `vms/<id>/` (mode 0700), removed when the VM stops, and by `terrarium ps` and `terrarium stop` when its process is gone; `console.log` is appended to across a Windows guest's restarts
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
* `shot` returns an image block (base64 PNG); `exec` returns stdout, stderr, and the exit status as text and `structuredContent`, each stream cut at 1 MiB, and a non-zero status is an error; `start` returns the ID and the owner's notes (including a generated Windows password), with `notifications/progress` when the request has a progress token
* calls run concurrently, each on a thread of its own; `notifications/cancelled` stops an `exec` (even one not yet connected), killing the guest's process, and gets no response; other tools are not cancellable and still answer; a request whose id is already in flight is -32600
* VMs outlive the server; it reaps the owner processes it starts

## helper

* listens on vsock port 4242 for `terrarium` requests, one per connection, each on its own thread
* a frame is a kind byte, a big-endian u32 length (at most 16 MiB), and the payload
* host → helper: `0x00` hello; `0x01` exec, JSON `{"argv": [...]}`; `0x02` clipboard get; `0x03` clipboard set (UTF-8 payload; answered by an exit frame of 0)
* helper → host: `0x00` hello (`terrarium-helper 1 <os>`); `0x10` stdout; `0x11` stderr; `0x13` clipboard text (UTF-8); `0x12` exit (big-endian i32: the exit code, all 32 bits on Windows, or the negated signal, 1 to 64); `0x1f` error (ends the exchange; also answers a frame over the limit)
* the Linux, macOS, and Windows helpers speak it; the Windows one reaches the host through the `viosock` Winsock provider, whose address family it asks the driver for
* the clipboard is the session's: `pbpaste` and `pbcopy` on macOS, the Win32 clipboard on Windows, and `wl-paste`/`wl-copy` or `xclip` (display `:0`, no `XAUTHORITY`) on Linux when a graphical session and the tool exist, which a root service rarely reaches; otherwise `0x1f` with "no clipboard"
* until a recipe installs it, a guest must be given the helper by hand

## image store

* store: `images/` in the support directory (see [modules](#modules))
* IMAGE is `<name>-<hash>`, a name without the hash that only one image has, or a unique prefix of the full name; an empty IMAGE or `--vm` matches nothing
* `pull` writes `*.partial.<pid>.<n>` (`n` counts the process's pulls, so concurrent ones keep apart), then renames it `<name>-<hash>.img`, the hash (16 hex digits) covering the source bytes and the converter's recipe version, keeping an existing file of that name; a local PATH needing no conversion is cloned with `clonefile(2)` when on the store's APFS volume, else copied; PATH must be a file, not a bundle
* `pull` identifies compression by magic bytes and decompresses `.xz` with the `Compression` framework's `COMPRESSION_LZMA` and `.gz` with `gunzip`, writing zero blocks as holes
* `pull` extracts the one file of a tar archive (magic `ustar`; an archive of several files is refused) and writes zero blocks as holes
* `pull` converts with `diskutil image create from` only when `diskutil image info` reports a format other than RAW; raw disks, ISOs, and macOS restore images (zip files) are stored as is
* `pull` converts a qcow2 image (magic `QFI\xFB`; version 2 or 3, plain or zlib-compressed clusters, no backing file, encryption, or extended features, tables within the file, a disk of at most 64 TiB; else refused) to RAW in-process; `start` and `run` refuse a stored qcow2 image
* images are stored read-only
* startup removes `*.partial.<pid>` and `*.partial.<pid>.<n>` files whose process is gone
* each `diskutil image attach` is recorded in `attached/` in the support directory (device, image, first-partition GUID, process); a disk attached blank is recorded again once partitioned; an eject that fails (after a forced unmount) keeps its record; startup ejects recorded images whose process is gone and whose GUID still matches, never others

## overlays

* one disk-change layer per VM via DiskImageKit; base images are read-only
* each VM writes to its own overlay, discarded on `stop` unless saved with `commit`
* `--overlay O` writes to a `clonefile(2)` copy of `O`, never `O` itself
* an image is **live** (boots as the read-only base of a VM's overlay) or an **installer** (an ISO or IPSW that `--install` consumes and never boots)
* an overlay is **dependent** (a layer over a live image, which it needs, or over an installed guest) or, for what `--install` leaves, an **installed guest** (complete on its own, bootable with no stored image)
* `commit` saves the whole overlay, treating `PATH` as a prefix: a dependent overlay as the file `PATH-<imagehash>.overlay` (`PATH-<guestid>.overlay` over a guest), an installed guest (what `--install` leaves, including a VM booted from a guest without `--overlay`) as the directory `PATH.guest` → `PATH'`; it refuses an existing file or a missing directory
* `commit` pauses the VM (unless it is paused), copies the layer off the main queue, and resumes, so the copy holds what the guest has flushed; a stop asked for meanwhile waits for it; a failed copy leaves no target; `--on-stop` copies after the VM stops
* an on-stop commit that fails, or that would save a VM that stopped with an error or an install that did not finish, saves nothing and moves the VM's files (including any password file) to `unsaved/<id>/` in the support directory
* an installed guest holds `manifest.json` (`guest` as `windows`, `macos`, or `linux`, `diskGB`, the `installer` image's name as provenance, and `id`, 16 hex digits chosen at `commit`), the layer, and for macOS the auxiliary storage, hardware model, and machine identifier
* `start` or `run PATH.guest` boots an installed guest with no `--install` or `--provision`; it clones all but the manifest, over a blank sparse disk of `diskGB` that terrarium regenerates
* `start` or `run PATH.guest --overlay O` boots the guest's layer read-only under a clone of `O`, a layer over it, or under a new layer when `O` does not exist (the first overlay over a guest); `commit` then saves `PATH-<guestid>.overlay` (for macOS a directory of the layer and the auxiliary storage), never a guest; a guest with no `id` (saved before ids) is refused, to boot and commit again
* `--overlay` takes only a dependent overlay, whose base must be the IMAGE or guest booted, and each flag rejects the other kind
* `start` and `run` reject a dependent overlay whose name hash differs from the image's or guest's `id`; a name without a hash consents to skip the check

## tweaks

* OS-specific changes to a guest (*e.g.*, settings): a script per tweak, run in the guest through the helper
* `tweak NAME` runs one in a running guest; `--tweak NAME` on `start` or `run` (repeatable) runs them, in the order given, once the helper answers; both use the same code
* `NAME` is `<os>/<name>` (`windows/edge-quiet`) or a bare `<name>`, which is the guest's own when its OS has one (`no-sleep` on a macOS guest) and otherwise must belong to only one OS
* the files are `core/tweaks/<os>/<name>.<ext>`, embedded by `build.zig` as `__TERRARIUM` sections like the recipes' scripts: `.ps1` for Windows, `.sh` for Linux and macOS
* a tweak's header is its leading comment lines (`#`, after any shebang): the first is what it does, and later `key: value` lines are settings, of which `timeout: SECONDS` is the first (default 10); unknown keys are ignored, so new ones can be added
* a tweak declares its OS by its directory; one that does not match the guest's, or an unknown name, is a usage error, found before a VM starts
* the helper runs it as `powershell -NoProfile -NonInteractive -EncodedCommand` (progress output off) or `sh -c`, with the privileges `exec` has; no stdin
* a tweak fails when it exits non-zero, cannot run, or outlasts its timeout (it and what it started are killed); a failure propagates as an exiting error: `tweak` exits with its status (124 for a timeout), and `start` or `run` stops the VM and exits 1, saying which tweak failed and showing its output
* `ps` shows state `tweaking` from the VM's start until its helper answers (for a macOS install, through the helper's installation), then `tweaking NAME` while one runs, then `running`; `start` returns when all have succeeded
* a tweak must be safe to run again; a change persists only if the overlay is committed
* only embedded tweaks, never paths
* each tweak's description and timeout are in the catalog, [docs/tweaks.md](docs/tweaks.md), which is their source of truth

## recipes

### shared

* boot-time guest setup, built on the host before the guest runs; independent of disk layout
* `--install RECIPE` (`alpine`, `macos`, `windows`) installs the installer IMAGE onto a new guest, and `--provision RECIPE` (`alpine`, `cloud-init`, `nocloud`) readies a live IMAGE's guest to be driven; they are alternatives, and `--install` takes no `--overlay` or guest; without either, the guest is untouched
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
* first boot only; the guest is saved as an installed guest

### `--provision alpine`

* `terrarium.apkovl.tar.gz` on a FAT volume, applied every boot: the helper, an OpenRC service in the default runlevel (loads `vmw_vsock_virtio_transport`), and `etc/.default_boot_services` so Alpine still adds its own; files owned by root

### `--install alpine`

* the ISO boots first (read-only), then the recipe's volume, then a blank 4 GB disk (sparse, in the VM's directory) with the overlay on top
* the apkovl's `local.d` hook runs `ERASE_DISKS=DISK setup-alpine -e -f` on the largest virtio disk from an answer file (US keymap, hostname `terrarium`, DHCP on `eth0`, UTC, `sys` mode, packages from the network's first mirror)
* then it removes the recipe's own files (the hook and `etc/terrarium`, which `setup-alpine` copies) from the new root, puts the helper, an OpenRC service, and the root password (random, or `--password`; printed once by `start`) into it, checks that root has a password, prints `terrarium: Alpine is installed` on the console, and powers off; any failed step prints why and powers off too
* save it with `commit --on-stop` first as an installed guest of kind `linux`, which boots from its own disk; it is saved only when `console.log` holds the success line

### `--provision cloud-init`

* NoCloud FAT volume labeled `CIDATA`: `user-data` writes the helper (base64) and a systemd unit and starts it, and `meta-data` takes the VM's ID as the instance ID, so every `start` runs it
* on a guest without systemd (Alpine's cloud images), it installs an OpenRC service for the helper instead and starts it, and limits cloud-init to the `NoCloud` and `None` datasources, so a later boot without `CIDATA` does not wait on others

### `--provision nocloud`

* for an image with no cloud-init that asks its questions on the text console (Debian's `nocloud` images): a FAT volume labeled `TERRARIUM` holds the helper and `install.sh`, which installs the helper as a systemd unit and starts it
* typed over VNC at fixed times after the VM starts (blind, as measured on Debian 13): a key for systemd's first-boot wizard, a skipped timezone, root's password (`--password`, else random and printed once by `start`, kept in `vms/<id>/nocloud-password` until the VM stops) and its confirmation, then a root login and the command that mounts the volume and runs `install.sh`, typed twice so a slower boot is covered
* the helper answers about 100 s after the start, and a committed overlay has the wizard's answers, the password, and the unit, so a later boot needs no `--provision`

### `--install windows`

* media: installer media (GPT disk: FAT32 boot tree, exFAT `install.wim`; built once per image) and a writable FAT boot disk (EFI shim, virtio-win drivers, install script, answer file, helper), both on USB
* the shim gives the firmware GOP a linear framebuffer and chainloads the installer, and puts back what it changed if the loaded image returns
* spaces (3 to 15 s), Shift+F10 (62 s), and `C:\install.cmd` (70 s) typed over VNC start the install script, which applies the Professional edition (found from the WIM's XML) to the boot disk, adds the drivers, copies the shim to the installed ESP, and shuts down
* `SetupComplete.cmd` makes the helper an at-logon task for the account at the highest run level, so it runs in the auto-logon session (the clipboard needs one) with the account's elevated rights, and is reachable once that logon completes; the installed system carries its own shim and is saved as an installed guest
* guests boot from NVMe over a blank base disk (40 GB by default; sparse, in the VM's directory), not the image; they get 8 GiB by default and the performance monitoring unit (private `_setPerformanceMonitoringUnitEmulationEnabled:`, checked before use)
* the answer file makes a local administrator (`--user`, default `terra`) with auto-logon and a random password (or the `--password` given; markup characters are escaped), printed once by `start` and kept in `vms/<id>/windows-password` until the VM stops when random
* the installer's shutdown stops the VM, so save the install with `commit --on-stop` first; the install script stops at the first failed step and writes `install.ok` to the boot disk only when every step succeeded, and once the VM stops, terrarium reads the boot disk read-only and, without the marker, shows the end of `install.log` and treats the install as not finished
* the virtio-win drivers (`viogpudo`, `NetKVM`, `viosock`; pinned URL and SHA-256) are downloaded once into `cache/`, as is the installer media; startup removes stale `*.partial.<pid>` files there too, and the `blank-disk-*` files of earlier versions
* a guest's reset stops the VM with an error; `start` and `run` restart it on the same disk and media, up to ten times, after stopping the VNC server
* a guest gets a new EFI variable store at every boot

## references and specifications

see [README.md](docs/specifications/README.md)
