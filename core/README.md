# core

`TerrariumCore`, in Swift: everything but a front-end, with no AppKit. `build.zig` compiles every `.swift` file under this directory as one module, so a new file needs no registration. The front-ends are [ui](../ui/README.md) and [cli](../cli/README.md); the module rules are in [AGENTS.md](../AGENTS.md).

The support directory is `Paths.support` ([Paths.swift](Paths.swift)); the front-end sets it before anything else runs.

Directories, lowest layer first; each uses only those above it in this table, and `tests/layers.py` checks it:

| Directory | Holds |
|---|---|
| `system/` | what everything shares: errors, running stock programs, descriptors and process checks, the VM control socket, the embedded guest files, and the private platform call |
| `images/` | the image store, `pull`, decompression, qcow2 and tar handling, hashing, and attached-image tracking |
| `display/` | the VNC server and RFB client behind `shot`, `click`, `type`, and `key`, and the keyboard mapping |
| `guestlink/` | the host side of the guest helper's vsock protocol, behind `exec`, `wait`, `put`, and `get` |
| `vm/` | the VM's disk, resources, and platform configuration (`config/`), and its state under `vms/<id>/` and the installed-guest manifest (`state/`) |
| `recipes/` | boot-time guest setup: the `--install` and `--provision` recipes, each with its guest files and notes |
| `tweaks/` | OS-specific scripts run in a guest through its helper (`<os>/<name>.<ext>`), and their catalog and header parsing |
| `owner/` | the owner process, headless: boot, restart, overlays, display-size tracking, and the actions a front-end calls |
| `verbs/` | the verb table, argument checks, `start` and `run` ([Launch.swift](verbs/Launch.swift)), the verbs that act on a running VM, and `Backend`, which performs each verb |

`images/`, `display/`, and `guestlink/` are one rank, and `recipes/` and `tweaks/` another: none uses another of its rank.

Private Virtualization APIs are confined to `system/PrivatePlatform.swift` and `display/PrivateVNC.swift`.

The sections below explain how it works; [AGENTS.md](../AGENTS.md) is the specification, and they add no requirements. `zig build run -- ps` runs the program through the build.

## Modules

The host is three Swift modules (`core/`, `ui/`, and `cli/`): `TerrariumCore` (no UI; everything a VM needs), `TerrariumUI` (the `run` window), and the `terrarium` executable (command line and MCP server). `build.zig` compiles the first two as static libraries with their `.swiftmodule`s, and the executable links them. The core's owner has no windows: a front-end hands it an `OwnerUI`, which the owner calls on the main queue when its state, its VM, or the guest's display size changes, and which runs the event loop. The window reads and acts on the owner through its public methods (`stopAndExit`, `saveOverlay`, `togglePause`, `sendKey`, `screenshot`). The core reads no environment; `main` sets `Paths.support` first.

## Tweaks

A tweak is a script in `core/tweaks/<os>/`, embedded like the recipes' files and named in `Tweaks.catalog`. The `tweak` verb and `--tweak` share one path: the owner connects to the guest's helper (trying each second until it answers), runs the script as `powershell -EncodedCommand` or `sh -c`, and kills it if it outlasts its timeout (closing the vsock connection does that, as for `exec`). `--tweak` runs them while the state is `tweaking NAME`, so `start` returns only once they have succeeded; a failure writes the tweak's output and a last line to the owner's log, which a waiting `start` reads, and the VM stops. A Windows guest that resets while one runs gets it again, since a tweak is safe to repeat. PowerShell takes a few seconds to start on a freshly booted guest, so a Windows tweak's header should ask for a longer `timeout`.

## Images

`pull` hashes the source bytes together with a recipe version, so the same download always gives the same name, `<name>-<hash>.img`, and a second pull is a no-op. Compression is recognized by its first bytes, not its file name. Zero blocks are written as holes, which keeps a 5.6 GB Fedora image to 2.5 GB on disk. Raw disks, ISOs, and macOS restore images (zip files) are stored as is; other disk formats are converted to RAW with `diskutil`. Stored images are read-only.

## One process per VM

Each running VM belongs to its own `terrarium` process. `start` re-launches the program in a new session and returns once the VM is running; `run` is the same process kept in the foreground with a window. The other verbs talk to that process over a Unix socket in the VM's directory, `vms/<id>/` in the support directory (`Paths.support`, `~/Library/Application Support/terrarium/` unless `$TERRARIUM_SUPPORT` says otherwise), which holds the overlay, firmware variables, console log, and `info.json`, and is removed when the VM stops.

The console log is the guest's first virtio console port, which Virtualization writes to `console.log`. A Linux guest sees it as `/dev/hvc0`, so `terrarium exec sh -c 'echo hello > /dev/hvc0'` adds a line to it (Show Console Log refreshes each second; `terrarium logs` prints it). Alpine's kernel console is `tty0`, so its boot messages are not in the log; a guest gets them there with `console=hvc0`.

A Windows guest's reset stops the VM with an error, and `start` and `run` restart it. The VNC server is stopped first: it would otherwise keep the old VM alive and stop the new one from starting.

## Overlays

A VM never writes to its base image. It writes to its own layer, made with DiskImageKit, and that layer is deleted when the VM stops unless you saved it with `commit`. `commit` pauses the VM, copies the layer, and resumes; what the guest has not flushed to its disk is not in the copy. With `--on-stop` the copy is made after the VM stops. The copy runs off the main queue, because a copy to another volume can take minutes and the VM's display and control socket share that queue. When an on-stop save cannot be made, or would save a VM that stopped with an error or an install that did not finish, the VM's files are moved to `unsaved/<id>/` in the support directory rather than deleted with `vms/<id>/`. `run`'s window has a menu for both. Saved overlays are named `PATH-<imagehash>.overlay` (`PATH-<guestid>.overlay` over a guest), so using one with the wrong image or guest is caught.

Images are *live* (the read-only base of a VM's overlay) or *installers* (an ISO or IPSW that `--install` reads and never boots); overlays are *dependent* (a layer over a live image, named for it) or an *installed guest* (made by `--install`). An installed guest is a directory, `PATH.guest`, holding the layer and a `manifest.json` (guest kind, disk size, and the installer's name as provenance). A macOS guest is more than a disk, since its identity (hardware model and machine identifier) and auxiliary storage belong to the installed system, so those three files are in the directory too. It boots over a blank sparse disk that terrarium makes again from the manifest's size, so it needs no stored image: `rmi` of the installer is safe, and `start GUEST` takes no stored image. A VM started from a guest commits as a new guest (a clone of its layer, which costs no extra space until the two diverge), so guests form chains the way dependent overlays do over a live image.

A guest also takes `--overlay`. The manifest's `id` is chosen at every `commit`, so a guest never changes after it is saved. With `--overlay`, DiskImageKit stacks the blank disk, the guest's layer (opened read-only, in place), and a clone of the overlay (a new layer when its path does not exist yet, which is how the first one is made), whose parent is the guest's layer; `commit` then saves only the top layer, so a variant costs only what it changed. DiskImageKit does not check the parent when stacking, so the overlay's name carries the guest's `id` and `start` compares them. A macOS overlay is a directory of the layer and the auxiliary storage, since the guest writes to both; the hardware model and machine identifier stay with the guest. Booting the same guest twice, with or without overlays, gives both VMs one machine identifier, as before.

## Recipes

A recipe is host-built setup that runs when the guest boots and puts the helper in. The VM's process builds it. `--install` recipes make a guest from an installer image; `--provision` recipes ready a live image or guest. `alpine` is one name under each flag; in the code, `Recipe` is an enum of `.install(NAME)` and `.provision(NAME)`, which the owner process's arguments and `info.json` carry as `install:NAME` and `provision:NAME`.

* `--provision alpine` puts an apkovl on a small FAT disk (built with `diskutil`) for Alpine's live ISO.
* `--provision cloud-init` puts a NoCloud `CIDATA` volume on one, using the VM's ID as the instance ID so every `start` runs it again.
* `--provision combustion` puts a `COMBUSTION` volume with a script and the helper on one, for openSUSE images that configure themselves with Combustion.
* `--provision nocloud` puts a `TERRARIUM` volume with the helper and an install script on one, and types the first-boot wizard's answers and a root login over VNC as the screen asks for them, read with Vision (see [recipes/nocloud](recipes/nocloud/README.md)).
* `--install windows` builds installer media and a boot disk, boots them over USB, and types the command that starts the install script over VNC. The scripts and the answer file are real files in `core/recipes/windows/`, embedded by `build.zig`. Windows boots from NVMe over a blank disk (40 GB unless `--disk` says more), not the ISO, and with a fresh set of firmware variables each time; the reasons are in [windows.md](recipes/windows/README.md). The installer's shutdown stops the VM, so `commit --on-stop` comes first. Since a failed install shuts down too, the script writes `install.ok` to the boot disk only after every step succeeded, and the owner reads the boot disk (attached read-only, after the VM has stopped) before it saves the guest.
* `--install alpine` boots the ISO with a blank disk and an apkovl hook that runs `setup-alpine` unattended onto it, adds the helper and a root password, and powers off. `setup-alpine` copies the live system's `/etc` into the new one, recipe included, so the hook removes itself and `/etc/terrarium` from the new root; until it did (fixed 2026-11-07), every boot of an installed guest ran the install again and failed quietly. The install counts as finished only once the console log holds its success line. It is the Linux install recipe, so it leaves an installed guest too, of kind `linux`. Packages come from the network's first mirror because the ISO lacks `grub-efi` and `dosfstools`.
* `--install macos` runs Apple's installer (`VZMacOSInstaller`) in the VM's process, from the restore image onto a blank disk (40 GB unless `--disk` says more), then boots the system with first-boot provisioning: the account `--user` names, automatic login, and Remote Login. It then logs in over SSH at the guest's NAT address, which it reads from the host's DHCP leases by the guest's MAC address, and installs the helper as a LaunchAgent, so it runs as the account, in its session (see [macos.md](recipes/macos/README.md)). The password reaches `ssh` through `SSH_ASKPASS` and `sudo -S`, never on a command line. Virtualization reads a restore image only under an `.ipsw` name, so the VM gets an APFS clone of the stored file.

`--install windows` and `--install macos` need the caller's agreement to the vendor's license (`--accept-license`). Without it, Windows stops at Microsoft's license page and macOS at Setup Assistant, and the caller finishes with `shot`, `click`, and `type`; the macOS helper is not installed then, because there is no account to log in to. The account is a separate choice, `--user`. Windows always creates one (the answer file does, and `terra` is the default), so the flags are independent there. On macOS, first-boot provisioning creates the account and skips Setup Assistant, which is where the license is agreed to, so `--user` needs `--accept-license` and `--accept-license` needs `--user`: terrarium asks for both rather than accept a license as a side effect of naming an account.

## The helper

`terrarium-helper` is a small static Zig program that listens on vsock port 4242 and runs commands for the host. Requests and replies are length-prefixed frames, described in [AGENTS.md](../AGENTS.md). The program is embedded in `terrarium`, so a recipe needs nothing else. On Windows it reaches vsock through the `viosock` driver's Winsock provider.

## Seeing and driving the guest

The screen, mouse, and keyboard go through Virtualization's private `_VZVNCServer`, bound to loopback with no security, and read by a small RFB client inside the VM's process. That is a private interface and can change with any macOS release. It is isolated in one file (`core/display/PrivateVNC.swift`) and every selector is checked before use.

`shot` nudges the pointer 1 px and back first, which wakes a sleeping display without a click and leaves hover state alone. The server answers a still screen only once per connection, so each retry samples on a connection of its own. The VNC server shares the main queue with the VM, so the RFB client runs on a background queue.

The VNC server's keyboard is Mac-style: X11 `Meta_L` reaches the guest as Alt, and `Alt_L` as the Windows key. `terrarium key` maps `alt` and `win` accordingly.

## The display's size

The guest's size is read from the VNC framebuffer, not from Virtualization's display object (`VZGraphicsDisplay`: `sizeInPixels`, `reconfigure(sizeInPixels:)`, and an observer). The object reports what the host last configured or requested. A guest that changes its own size (as every guest below did) moves the framebuffer and nothing else: no change to `sizeInPixels` and no observer call. Checked 2026-11-07, driving each guest's own settings while logging the object, its observer, and VNC:

| Guest | Change | VNC | `sizeInPixels` and observer |
|---|---|---|---|
| macOS 27.2 | System Settings > Displays: 1280x800 to 1024x640 | 1024x640 | stayed 1280x800; no event |
| Fedora 44 GNOME | Settings > Displays: 1280x800 to 1024x768 | 1024x768 | stayed 1280x800; no event |
| Windows 11 ARM64 | the display driver loads (1280x800 to 1024x768 about a minute in, and again after each of two resets) | each change | stayed 1280x800; no event |

Host requests (`reconfigure`) are honored by macOS and by Linux's virtio GPU, up to a limit: 3840x2400 and 5120x2880 worked, and 16384x16384 left a Fedora guest stuck at 4096x2160, ignoring later requests, while the object reported what had been asked. Windows ignores them (accepted, observer called, no change). Windows' own Display resolution control is disabled with this driver.

A guest that ignores host requests keeps its own size: Windows always, and GNOME once a mode has been chosen in its Settings (the window's resize still reaches Virtualization, which reports it to the observer, but the guest does not act). The [window](#the-run-window) therefore follows the guest's shape and never the other way round. Checked on Fedora GNOME on 2026-11-07: Settings to 1920x1080 turned a 640x400 window into 640x360.

The VNC server announces a size change (the RFB desktop-size pseudo-encoding) on a connection held open and asking for a 1x1 corner of the screen, so nothing is polled and the owner is idle at 0.0% CPU; a thread reconnects when a Windows reset replaces the server. A booting guest passes through firmware modes (Windows sits at 1280x720 for about seven seconds after each reset), so `ps` shows a new size once it has held for a second. Guest-initiated changes in Fedora GNOME reached `ps` in about 1.6 seconds.

## The run window

A `run` window never asks the guest to resize: the guest keeps its size (only the guest changes it, which the watcher above follows) and the window is a view of it at a scale. The rules for the scale, the aspect ratio, and when the window takes a new shape are in [AGENTS.md](../AGENTS.md#run-window).

View > Match Guest to Window is the one request the host makes: it asks the guest for the window's size in pixels, and a guest that follows keeps the window's size, so the scale becomes 100%, pixel-exact. Checked on Fedora GNOME on 2026-11-07: a 1280x800-point window at 200% around a 1280x800 guest became a 2560x1600 guest in a window of the same size at 100%, taking about 11 seconds while the guest was still booting. After a mode chosen in GNOME's Settings, the request was ignored and nothing changed. Windows ignores it too (not rerun with this command).

## Known gaps

* `pull` cannot read qcow2 images with a backing file, encryption, or zstd compression, or choose among the files of a tar archive (it takes one holding a single file)
* the `run` window's scale, aspect, and Match Guest to Window were checked on Fedora through test hooks (since removed); the window on Windows and macOS, real edge drags, and the menus clicked by hand have not been tried
* the Windows installed helper never updates itself
