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
| `start` | `start [IMAGE\|PATH.guest] [OPTIONS]` | ID |
| `run` | `run [IMAGE\|PATH.guest] [OPTIONS] [--commit-on-stop PATH]` | ID |
| `commit` | `commit ID PATH [--on-stop]` | the saved path |
| `stop` | `stop ID` | ID |
| `ps` | `ps` | running VMs: ID, image, state, display size, whether it has a window, start time |

`start` returns once the VM is running (and any `--tweak` has succeeded); if the guest stops itself within two seconds of that, it fails with "the guest stopped itself" (the image is probably not bootable). `run` stays in the foreground and shows the VM in a window.

### Options of `start` and `run`

| Option | Meaning |
|---|---|
| `--memory MB` | MiB; 4096 by default, 8192 for Windows and macOS |
| `--cpus N` | the Mac's count, 2 to 4 by default |
| `--user NAME` | the account `--install` creates (`windows` always, default `terra`; `macos` only with this and `--accept-license`) |
| `--password PW` | that account's password (root's, with `--provision nocloud`); random by default and printed once by `start`; `run --password -` reads it from standard input (a prompt without echo on a terminal) and never prints it |
| `--disk GB` | the new guest's disk size with `--install`: 4 to 1000 for `alpine`, 40 to 1000 for `macos` and `windows` (default: the least) |
| `--accept-license` | your agreement to the guest vendor's license, with `--install windows` or `macos` |
| `--overlay PATH` | start from a copy of a dependent overlay |
| `--install RECIPE` | `alpine`, `macos`, or `windows`: install an installer image onto a new guest |
| `--provision RECIPE` | `alpine`, `cloud-init`, `combustion`, or `nocloud`: ready a live image's guest to be driven |
| `--tweak NAME` | run a [tweak](tweaks.md) once the helper answers; repeatable |

`commit` saves a dependent overlay as `PATH-<imagehash>.overlay` (`PATH-<guestid>.overlay` over a guest) and an installed guest as the directory `PATH.guest`.

```
terrarium start alpine-virt --provision alpine --tweak linux/no-blank
terrarium commit ID ~/vms/alpine --on-stop
terrarium run alpine-virt --overlay ~/vms/alpine-HASH.overlay
```

## Observe and control

Each takes `--vm ID`, defaulting to the only running VM.

| Verb | Synopsis | Notes |
|---|---|---|
| `shot` | `shot` | PNG on stdout; the coordinates of `click` are relative to it |
| `logs` | `logs` | the VM's console log |
| `click` | `click X,Y [--button B] [--drag-to X,Y] [--scroll DX,DY]` | `B` is `left`, `middle`, or `right`; positive scrolls go down and right |
| `type` | `type TEXT` | US-keyboard ASCII; newline is Return |
| `key` | `key [CHORD+]KEY` | modifiers `ctrl`, `shift`, `alt`, `win`, as in `ctrl+shift+n` |
| `exec` | `exec COMMAND [ARGS...]` | no shell, empty stdin; exits with the command's status |
| `tweak` | `tweak NAME` | see [tweaks](tweaks.md) |
| `wait` | `wait [--down \| --reboot] [--timeout SECONDS]` | prints `ready` once the VM is `running` (tweaks done) and its helper answers; fails at the timeout (default 600) or if the VM stops. `--down` waits for the opposite and prints `down`: the VM has stopped (any on-stop commit saved), or its helper stopped answering after it had. A guest that restarts between two polls (every 0.5 s) is missed. `--reboot` waits for the guest to restart instead and prints `rebooted`: its helper (which starts again at boot) answers with a new instance ID, not the one the last `wait` found. So `wait`, then `exec reboot`, then `wait --reboot` cannot miss a fast restart; with no earlier `wait`, the first instance it sees is the baseline |
| `put` | `put HOST_PATH GUEST_PATH` | a file, or a directory's regular files under GUEST_PATH; makes missing guest directories; absolute guest paths only (Windows: with a drive letter) |
| `get` | `get GUEST_PATH HOST_PATH` | one file; HOST_PATH is a file, or a directory to put it in |
| `clipboard` | `clipboard get` \| `clipboard set TEXT\|-` | UTF-8, at most 1 MiB; `-` reads standard input (command line only) |

`put` and `get` write each file whole or not at all (a partial file beside it is renamed over it at the end). `put` keeps a file's mode on Linux and macOS guests, and skips symlinks, empty directories, and other kinds of entry, saying how many.

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
