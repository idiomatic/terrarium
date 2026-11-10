# Verbs

Each verb is a `terrarium` subcommand and an MCP tool of the same name and parameters, except `run` (CLI only). [AGENTS.md](../AGENTS.md) holds the requirements; this page is the reference. `terrarium help` lists the verbs from the code, and `terrarium help VERB` shows a verb's arguments.

## Images

| Verb | Synopsis | Prints |
|---|---|---|
| `pull` | `pull URL\|PATH` | IMAGE |
| `images` | `images` | stored images, one per line, with the `--install` recipe each needs, `macos` or `windows`, or none (INSTALL) |
| `rmi` | `rmi IMAGE` | the removed image's name |

An IMAGE is its name without the hash when only one image has that name, else `<name>-<hash>`, or a unique prefix of that.

```
terrarium pull https://example.com/alpine-virt.iso
terrarium images
terrarium rmi alpine-virt
```

## Lifecycle

| Verb | Synopsis | Prints |
|---|---|---|
| `start` | `start [IMAGE\|LAYER] [OPTIONS]` | ID |
| `run` | `run [IMAGE\|LAYER] [OPTIONS]` | ID |
| `commit` | `commit ID (LAYER \| --save CHILDLAYER \| --clone SIBLINGLAYER \| --continue \| --ephemeral) [--on-stop]` | the saved layer's path |
| `stop` | `stop ID` | ID |
| `ps` | `ps [--deceased]` | running VMs: ID, image, state, display size, whether it has a window, start time; with `--deceased`, the last 20 VMs that ended: ID, image, start and end times, exit status, and why (stopped by `stop`, the guest stopped itself, its process is gone, an error), with where a scheduled commit saved it |

`start` returns once the VM is running (a guest with a terrarium helper shows `booting` in `ps` until the helper answers; `start` does not wait for that, `wait` does) (and any `--tweak` has succeeded); if the guest stops itself within two seconds of that, it fails with "the guest stopped itself" (the image is probably not bootable). `run` stays in the foreground and shows the VM in a window.

### Options of `start` and `run`

| Option | Meaning |
|---|---|
| `--memory MB` | MiB; 4096 by default, 8192 for Windows and macOS |
| `--cpus N` | the Mac's count, 2 to 4 by default |
| `--user USERNAME` | the account `--install` creates (`windows` always, default `terra`; `macos` only with this and `--accept-license`) |
| `--password PW` | that account's password (root's, with `--provision nocloud`); random by default and printed once by `start`; `run --password -` reads it from standard input (a prompt without echo on a terminal) and never prints it |
| `--disk GB` | the new guest's disk size with `--install`: 4 to 1000 for `alpine`, 40 to 1000 for `macos` and `windows` (default: the least); the disk is sparse and takes only what the guest writes (a clean Windows install is about 16 GB) |
| `--ephemeral` | discard the VM's work when it stops (unless a `commit` saved it); `start` needs this or one of the next three, which are alternatives |
| `--save CHILDLAYER` | when the VM stops, save its work as the new layer CHILDLAYER, a child of what it started from (an install: a root layer); checked before anything starts |
| `--clone SIBLINGLAYER` (or `--save-sibling`) | with a layer: save the layer's changes and the VM's as the sibling SIBLINGLAYER |
| `--continue` (or `--save-over`) | with a layer: save back to the layer, replacing it atomically; a layer another VM will save cannot be saved by a second |
| `--accept-license` | your agreement to the guest vendor's license, with `--install windows` or `macos` |
| `--install RECIPE` | `alpine`, `macos`, or `windows`: install an installer image onto a new root layer |
| `--provision RECIPE` | `alpine`, `cloud-init`, `combustion`, or `nocloud`: ready a live image's guest to be driven |
| `--tweak TWEAK` | run a [tweak](tweaks.md) once the helper answers; repeatable |

`commit` saves the VM's delta as a layer, a `NAME.layer` bundle: a bare NAME goes in the layer store (`~/Library/Application Support/terrarium/layers/`), a path where it points. Starting from an image or a layer, it is a child of that; a VM started with `--clone` or `--continue` saves a sibling of the layer, which for `--continue` replaces it (the old one is swapped out atomically). An install saves a root layer. The options are the start options' words: `--save CHILDLAYER` (a child), `--clone SIBLINGLAYER` or `--save-sibling` (a sibling), `--continue` or `--save-over` (replace the starting layer), and `--ephemeral`, which cancels a scheduled save so the work is discarded when the VM stops (it releases the layer's name). `--save` is refused for a VM started with `--clone` or `--continue`, whose delta already holds the layer's changes; `--clone` and `--continue` are refused for any other VM. A bare `LAYER` is `--save`, or `--clone` for a VM started with `--clone` or `--continue`.

```
terrarium start alpine-virt --provision alpine \
  --tweak linux/no-blank --save alpine
terrarium run alpine
terrarium run alpine --clone alpine2
terrarium run alpine2 --continue
```

## Layers

| Verb | Synopsis | Prints |
|---|---|---|
| `layers` | `layers` | the layer store as a tree: images that have layers as roots, a layer under its parent |
| `rm` | `rm LAYER` | the removed layer's name |

`rm` leaves the layers made from the removed one whole, since each holds its own clones of its ancestors' files. A layer whose parent is gone appears as a root marked `(gone: ID)`.

## Observe and control

Each takes `--vm ID`, defaulting to the only running VM.

| Verb | Synopsis | Notes |
|---|---|---|
| `shot` | `shot` | PNG on stdout, a second after the last input; the coordinates of `click` are relative to it |
| `logs` | `logs` | the VM's console log |
| `click` | `click X,Y [--button B] [--drag-to X,Y] [--scroll DX,DY]` | `B` is `left`, `middle`, or `right`; positive scrolls go down and right |
| `resize` | `resize WxH` | asks the guest for a display of that size in pixels (macOS and Linux's virtio GPU follow, up to a limit; Windows has not, see [windows.md](windows.md)) |
| `move` | `move X,Y` | moves the pointer without a click, to keep it out of a `shot` |
| `type` | `type TEXT` | US-keyboard ASCII; newline is Return |
| `key` | `key [CHORD+]KEY` | modifiers `ctrl`, `shift`, `alt`, `win`, as in `ctrl+shift+n` |
| `exec` | `exec COMMAND [ARGS...]` | no shell, empty stdin; exits with the command's status |
| `tweak` | `tweak TWEAK` | see [tweaks](tweaks.md) |
| `wait` | `wait [--down \| --reboot] [--timeout SECONDS]` | prints `ready` once the VM is `running` (not `booting` or `tweaking`) and its helper answers; fails at the timeout (default 600) or if the VM stops. `--down` waits for the opposite and prints `down`: the VM has stopped (any on-stop commit saved), or its helper stopped answering after it had. A guest that restarts between two polls (every 0.5 s) is missed. `--reboot` waits for the guest to restart instead and prints `rebooted`: its helper (which starts again at boot) answers with a new instance ID, not the one the last `wait` found. So `wait`, then `exec reboot`, then `wait --reboot` cannot miss a fast restart; with no earlier `wait`, the first instance it sees is the baseline |
| `put` | `put HOST_PATH GUEST_PATH` | a file, or a directory's regular files under GUEST_PATH; makes missing guest directories; absolute guest paths only (Windows: with a drive letter) |
| `get` | `get GUEST_PATH HOST_PATH` | one file; HOST_PATH is a file, or a directory to put it in |
| `clipboard` | `clipboard get` \| `clipboard set TEXT\|-` | UTF-8, at most 1 MiB; `-` reads standard input (command line only) |

`put` and `get` write each file whole or not at all (a partial file beside it is renamed over it at the end). `put` keeps a file's mode on Linux and macOS guests, and skips symlinks, empty directories, and other kinds of entry, saying how many.

A command that outlasts a client's patience should not run under `exec`: a Linux or macOS guest takes it detached, with its output in a file (`terrarium exec sh -c 'setsid sh -c "make > /tmp/build.log 2>&1" </dev/null >/dev/null 2>&1 &'`), which `terrarium get /tmp/build.log .` or a short `exec` reads later; `exec` kills what it started, its process group (a job object on Windows), when its connection ends, and `setsid` leaves the group.

`exec` exit statuses: the command's own; 128 plus the signal number if it was killed; 1 for a code outside 0 to 255.

```
terrarium shot > screen.png
terrarium click 640,400
terrarium type "hello"
terrarium key ctrl+alt+delete
terrarium exec uname -a
echo hi | terrarium clipboard set -
terrarium wait
terrarium exec poweroff; terrarium wait --down
terrarium wait; terrarium exec reboot; terrarium wait --reboot
terrarium put ~/src/app /home/debian/app
terrarium get /home/debian/app/out.log ~/Downloads
```

## MCP

Tool and argument names are the verbs' and parameters' own, plus `vm` and, for `exec`, `args`. Flags are booleans; `memory` and `cpus` are integers. `shot` returns an image block; `exec` returns stdout, stderr, and the exit status, each stream cut at 1 MiB.
