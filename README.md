# terrarium

Boot macOS, Linux, and Windows guests on a Mac, then see and drive them from the command line or from an agent: take screenshots, click, type, press keys, and run commands. The same verbs are also a stdio [MCP](docs/specifications/README.md) tool (`terrarium mcp`).

![The terrarium flow: pull an image, then start or run it into an install lane or a use lane, drive the VM, commit it as a layer, and start again from what you saved](docs/flow.svg)

[AGENTS.md](AGENTS.md) is the specification. This file explains how to use terrarium and adds no requirements of its own; how it works inside is in [core/README.md](core/README.md).

## What you need

* a Mac with Apple silicon, running macOS 27 or later
* Xcode, for `swiftc` and the SDK
* [Zig](https://ziglang.org) 0.17 or later

```
zig build
```

builds `zig-out/bin/terrarium`, signed with the entitlement Virtualization requires. Put it on your `PATH` to follow the walkthroughs. At run time terrarium calls only programs that ship with macOS and links no external libraries.

Xcode and Zig are needed only to build it. A prebuilt binary for Apple silicon is on the [releases page](https://github.com/idiomatic/terrarium/releases): unpack it and put it on your `PATH`.

> [!NOTE]
> The prebuilt binary is signed only ad hoc, not notarized, so Gatekeeper blocks one downloaded with a browser. Allow it under System Settings › Privacy & Security › Open Anyway, or clear the quarantine flag:
>
> ```
> xattr -d com.apple.quarantine terrarium
> ```

## Quick start

A Debian cloud image, headless:

```
base=https://cloud.debian.org/images/cloud/trixie/latest
terrarium pull $base/debian-13-genericcloud-arm64.raw
id=$(terrarium start debian-13 --provision cloud-init \
       --ephemeral --memory 2048 --cpus 2)
terrarium wait
terrarium exec uname -a
terrarium put ~/src/app /home/debian/app
terrarium shot > screen.png
terrarium commit $id dev
terrarium stop $id
terrarium start dev --ephemeral
```

1. `terrarium pull` prints the image's name.
2. `terrarium start` prints the VM's ID.
3. `terrarium commit` prints the layer it wrote, `.../layers/dev.layer`.
4. The layer already has the helper, so the last `start` needs no `--provision`.

[Layers](#layers) says more about saving and reusing a VM's work.

## How it works

Every VM starts the same way, then goes down one of two lanes: **INSTALL**, which turns an installer image into a layer, or **USE**, which runs a live image or a layer.

1. **`terrarium pull`** stores a disk image: a URL or a file, such as an ISO, an IPSW, or a raw or compressed disk. Stored images are read-only and named `NAME-HASH`; any unique prefix works as a name.
2. **`terrarium start`** boots a VM without a window and prints its ID (*headless*); **`terrarium run`** boots it in a window and stays until you close it (*interactive*). Both take an IMAGE, or a LAYER you saved.
3. **The lane follows the flag.** `--install RECIPE` (`windows`, `macos`, or `alpine`) sends the VM down INSTALL: the image is an *installer* (a Windows ISO, a macOS IPSW, or Alpine's ISO), which the recipe installs from and the VM never boots as is. Anything else goes down USE: the image is *live* (it boots as the base of the VM's disk, such as a Debian cloud image), or the VM starts from a saved layer. `--provision RECIPE` (`cloud-init`, `alpine`, or `nocloud`) readies a USE guest by putting the guest helper in, so that `terrarium exec` works.
4. **Drive it**, in either lane. `terrarium shot` takes a PNG of the screen, and `terrarium click`, `terrarium type`, and `terrarium key` act on it. `terrarium exec` runs a command in the guest and returns its output and exit status. `terrarium stop` stops any running VM, an install included. Verbs that act on a VM take `--vm ID`; without it they use the only running VM.
5. **Say what becomes of the VM's work.** It is lost when the VM stops unless saved as a layer; `terrarium start` needs you to choose (see [Layers](#layers)). After an install, `terrarium rmi` the installer to get its space back.

## Layers

A *layer* is a saved VM disk: a `NAME.layer` folder holding the VM's changes and its own copy of everything those changes sit on. An install saves a *root layer*, which needs no image. Anything else saves a layer that descends from the image or layer you started from.

You choose where a VM's work goes when you start it, and can change that later with `commit`:

| Option | When the VM stops | Chain |
|---|---|---|
| `--ephemeral` | the work is discarded | nothing is saved |
| `--save CHILDLAYER` | the work is saved as a new layer named CHILDLAYER, a *child* of the image or layer you started from | one longer |
| `--clone SIBLINGLAYER` | the work is saved as SIBLINGLAYER, a *sibling* of the starting layer: it keeps the starting layer's changes plus yours, and the starting layer is left as it was | the same length |
| `--continue` | the work is saved back to the starting layer, which is replaced atomically | the same length |

`--clone` and `--continue` start from a layer, not an image. `--save-sibling` and `--save-over` are the same options as `--clone` and `--continue`, under names that say they are outputs.

`terrarium commit ID` takes the same words for a VM that is already running (`--save`, `--clone`, `--continue`, and `--ephemeral`, which cancels a scheduled save), saving now or, with `--on-stop`, when the VM stops. A bare `commit ID LAYER` is shorthand for `--save`, or for `--clone` when the VM started with `--clone` or `--continue`. A plain `stop` discards what nothing saved.

![When the work is saved (at launch, spontaneously with commit, or on stop) and what each option saves relative to the starting layer](docs/saving.svg)

```
terrarium start debian-13 --provision cloud-init \
  --save base
terrarium start base --save toolchain
terrarium start toolchain --clone experiment
terrarium start experiment --continue
terrarium layers
terrarium rm experiment
```

`base` descends from the Debian image, `toolchain` from `base`, `experiment` is a copy of `toolchain` that kept what you did, and `--continue` keeps working in `experiment` without making the chain longer. Pick `--save` for a base you want to keep, `--clone` to try something without touching the original, and `--continue` to carry on one piece of work over many sessions.

**Naming.** A bare `NAME` is a layer in the layer store, `~/Library/Application Support/terrarium/layers/NAME.layer`. An argument with a `/`, a leading `~`, or ending `.layer` is that path, so a layer can live (and be moved) anywhere. A name that is both an image's and a layer's is refused. `commit` and the save options will not overwrite an existing layer, except that `--continue` replaces the one it started from.

**Listing and removing.** `terrarium layers` shows the store as a tree, images with layers at the top and each layer under its parent, with the size of its own changes (DELTA) and of the copies of its ancestors (CHAIN, which share disk blocks with the originals). A layer whose parent is gone shows as `(gone: ID)`. `terrarium rm LAYER` removes one, but not while a running VM started from it.

**Parents are optional.** Each layer holds its own copy of its ancestors' files, made by cloning (free on the same APFS volume until they diverge). So removing a parent, even the image, leaves its children whole, and a layer can be moved anywhere. Copying one with `cp -c` clones it; a copy to another volume, or one made without cloning (`rsync`, Finder), writes each file out in full and can take far more space than the original did.

**Keeping layers small.** A layer grows with what the guest writes, and deleting files does not shrink it. Run the `trim` tweak before you save (`--tweak trim` on Windows or Linux): it tells the virtual disk which blocks are free.

**Several VMs at once.** Many VMs may start from one layer, each writing its own delta; only one may save to a given name. The VM that will save a layer holds a lock on its name, so a second VM aiming at it is refused when it starts, not when it stops. A VM clones the layer it starts from, so a `--continue` VM that replaces the layer does not change what another VM started from it reads or saves; that VM keeps the old contents until it stops. If a `--continue` VM's layer is moved or removed meanwhile, its save at stop is refused, not recreated under the old name, and its files are kept in `unsaved/`. If a VM or the Mac dies, the layer is as the last save left it.

**Older files.** `.guest` folders and `.overlay` files from earlier versions are not read; install again.

## The interactive run window

* The title shows the VM's state. Closing the window stops the VM.
* *File* menu: *Commit…* and *Commit When VM Stops…* (what `terrarium commit` does), *Screenshot…*, *Reveal VM Folder*, and *Copy VM ID*.
* *Edit* menu: *Paste to Guest* (Command-V) and *Copy from Guest* (Command-C) move text between the host's pasteboard and the guest's clipboard; *Share Clipboard* (off by default) does it whenever the window gains or loses focus. Both need a running guest with a helper.
* *VM* menu: *Pause*; *Send Key*, for chords the host keeps, such as Ctrl+Alt+Delete or Cmd+Tab (Escape and the guest OS's own shortcuts, each named by its effect); and *Capture System Keys*, off by default so Cmd-Tab and screenshots stay yours (turn it on to give the guest every shortcut).
* *Window* menu: *Console Log*.

## Verbs

`terrarium help` lists the verbs, and `terrarium help VERB` shows a verb's arguments. `terrarium --version` (or `terrarium version`) shows the version.

* images: `pull` (a URL or a file), `images`, `rmi`
* lifecycle: `start` (headless), `run` (in a window; CLI only), `commit`, `stop`, `ps`
* layers: `layers`, `rm`
* observe and control: `shot`, `logs`, `click`, `type`, `key`, `exec`, `put`, `get`, `clipboard`, and `wait`, which returns once the VM is running, its tweaks are done, and its helper answers
* tweaks: `tweak` runs an embedded OS-specific script in the guest, and `--tweak TWEAK` on `start` and `run` does the same once the guest's helper answers; run one, then save the layer to keep it (see [Layers](#layers))

Recipes today: `--install` takes `alpine`, `windows`, and `macos`; `--provision` takes `alpine`, `cloud-init`, `combustion`, and `nocloud`. [docs/verbs.md](docs/verbs.md) details every verb and option, and [docs/tweaks.md](docs/tweaks.md) catalogs the tweaks and says how they fail.

## Use it from an agent

`terrarium mcp` serves every verb but `terrarium run` as an MCP tool on stdin and stdout. A client configuration:

```
{"command": "terrarium", "args": ["mcp"]}
```

Claude Code, in a project's `.mcp.json` (or `claude mcp add terrarium -- terrarium mcp`):

```
{
  "mcpServers": {
    "terrarium": {"command": "terrarium", "args": ["mcp"]}
  }
}
```

OpenCode, in `opencode.json`:

```
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "terrarium": {"type": "local", "command": ["terrarium", "mcp"], "enabled": true}
  }
}
```

Use the full path to `terrarium` if it is not on the client's `PATH`. A session starts with `pull`, `start`, and `wait`; then `exec`, `put`, `get`, and `shot` drive the guest.

Other sessions may share the Mac's terrarium, so a client does well to prefer the VMs it started, name them with `vm`, and save what it makes as a new layer instead of replacing one (see [Layers](#layers)). The server's instructions say so.

VMs outlive the server. `terrarium exec` returns stdout, stderr, and the exit status, and a client's cancellation kills the guest's process.

## Good to know

* `terrarium stop` powers the VM off; it does not ask the guest to shut down.
* `/bin/ps` shows a password given with `--password`.
* `terrarium pull` converts qcow2 images (version 2 or 3, with plain or zlib-compressed clusters) to raw disks, and extracts the disk image from a tar archive that holds just one file (a `.tar.gz` of `disk.raw`, say). It cannot read qcow2 images with a backing file, encryption, or zstd compression, or choose among the files of a larger archive.
* A guest's screen and keyboard are served on a loopback VNC port with no authentication, so any local process, including another user's, can watch and drive every running guest.
* On Linux, the clipboard needs `wl-clipboard` or `xclip` and a graphical session the root helper can reach; on most desktops it cannot, and `clipboard set` types the text instead.
* Closing the `run` window's app at logout stops the VM but cancels the logout (the VM's stop cannot finish otherwise), so log out again.
* terrarium relies on private Virtualization interfaces for the screen and keyboard, which can change with any macOS release.
* Windows and macOS guests are installed from the vendors' images under the vendors' licenses, which are yours to accept.

## More

Walkthroughs, headless (`terrarium start`: no window, driven by commands or an agent) and interactive (`terrarium run`: a window you use yourself), with what it took to boot each OS:

* [Linux](docs/linux.md): Alpine, Debian, Fedora, and Ubuntu
* [macOS](docs/macos.md)
* [Windows](docs/windows.md)

Reference:

* [docs/distros.md](docs/distros.md): images to pull (Ubuntu, Debian, Fedora, Alpine, macOS, Windows, and more), how far each has been tested, and the recipe and tweaks for each
* [docs/specifications/README.md](docs/specifications/README.md): the external specifications

Inside:

* [core/README.md](core/README.md): how it works
* [core/recipes/macos](core/recipes/macos/README.md) and [core/recipes/windows](core/recipes/windows/README.md): what it took to install and drive each

## Credits

terrarium was written with [Claude](https://claude.com/).

## License

BSD 3-Clause; see [LICENSE](LICENSE).
