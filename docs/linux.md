# Linux guests

## Alpine Linux

**Interactive, ephemeral.** Alpine's live ISO in a window; the VM's changes are discarded when it stops (only the pulled image stays in the store):

```
base=https://dl-cdn.alpinelinux.org/alpine/v3.24
terrarium pull \
  $base/releases/aarch64/alpine-standard-3.24.4-aarch64.iso
terrarium run alpine-standard-3.24.4 --provision alpine
```

Log in as `root` (no password) and use the window as a machine. From another terminal, `terrarium exec uname -a` and `terrarium shot` still work on it.

**Install.** The same ISO can also be installed onto a disk, which makes a guest that boots by itself:

```
mkdir -p ~/vms
terrarium run alpine-standard-3.24.4 --install alpine \
  --password - --commit-on-stop ~/vms/alpine
```

1. `terrarium run` asks for the root password (hidden on a terminal; it can also come from standard input) and never prints it. The window shows the installer working; the install takes under a minute and fetches its packages from Alpine's first mirror, so the VM needs the network.
2. The installer powers the VM off when it is done, the window closes, and `--commit-on-stop` saves `~/vms/alpine.guest`.

**Interactive, persistent.** Boot the installed guest with the repositories and console tweaks, and keep their changes:

```
terrarium run ~/vms/alpine.guest \
  --tweak alpine-repositories \
  --tweak no-blank \
  --commit-on-stop ~/vms/alpine-ready
```

Log in as `root` with the password you gave. Closing the window saves `~/vms/alpine-ready.guest`; leave `--commit-on-stop` off to discard the tweaks' changes.

**Headless, installed.** The same install and tweaks, driven by commands:

```
mkdir -p ~/vms
id=$(terrarium start alpine-standard-3.24.4 \
       --install alpine)
guest=$(terrarium commit $id ~/vms/alpine --on-stop)
while terrarium ps | grep -q $id; do sleep 5; done
id=$(terrarium start $guest \
       --tweak alpine-repositories \
       --tweak no-blank)
ready=$(terrarium commit $id ~/vms/alpine-ready --on-stop)
terrarium exec cat /etc/alpine-release
terrarium exec cat /etc/apk/repositories
terrarium stop $id
```

1. The first `terrarium start` installs as above, and prints the root password once (`--password PW` chooses it). `terrarium commit --on-stop` schedules the save for when the installer powers the VM off.
2. The second `terrarium start` boots that guest. The installed system has only Alpine's `main` repository enabled; `--tweak alpine-repositories` adds `community`, and `--tweak no-blank` keeps the text console from blanking, which `terrarium shot` would otherwise capture as black.
3. `terrarium start` returns once the tweaks have run, so `exec` works at once.
4. The second `commit --on-stop`, scheduled before `stop`, saves `~/vms/alpine-ready.guest` with the tweaks' changes; skip it and `stop` discards them.

**Headless, cloud image.** Alpine also publishes [cloud images](https://alpinelinux.org/cloud/), which install nothing themselves and take the same steps as Debian's. Take the aarch64 qcow2 of the `cloudinit` variant (the `tiny` one uses Tiny Cloud, which `--provision cloud-init` does not drive):

```
mkdir -p ~/vms
base=https://dl-cdn.alpinelinux.org/alpine/v3.24
terrarium pull \
  $base/releases/cloud/alpine-3.24.4-aarch64-cloudinit-r0.qcow2
id=$(terrarium start alpine-3.24.4-aarch64-cloudinit \
       --provision cloud-init)
terrarium wait
terrarium exec cat /etc/alpine-release
overlay=$(terrarium commit $id ~/vms/alpine-cloud)
terrarium stop $id
terrarium start alpine-3.24.4-aarch64-cloudinit --overlay $overlay
```

The helper runs as root, and it is an OpenRC service the overlay already has, so the last `start` needs no `--provision` and answers in about 20 seconds. The image's own login user is `alpine`; the walkthrough does not use it.

## Debian Linux

**Headless.** A Debian cloud image, which installs nothing itself, is the [README](../README.md#quick-start)'s quick start.

## Fedora Linux

**Interactive, ephemeral.** Fedora's Workstation Live ISO boots to a GNOME session by itself; the VM's changes are discarded when it stops (only the pulled image stays in the store):

```
base=https://download.fedoraproject.org/pub/fedora/linux
base=$base/releases/44/Workstation/aarch64/iso
terrarium pull \
  $base/Fedora-Workstation-Live-44-1.7.aarch64.iso
terrarium run Fedora-Workstation
```

It reaches the welcome screen after about a minute and a half. Press *Not Now* to use the live session. Everything in it is discarded when you close the window; this image is for trying Fedora, not for setting it up (see the persistent example below). The image has no helper and no recipe for it yet, so `terrarium exec` is not available; `terrarium shot`, `terrarium click`, `terrarium type`, and `terrarium key` work, and `terrarium logs` shows the serial console.

**Interactive, persistent.** The Workstation live session lives in memory, so there is little to keep. To keep changes, pull the cloud image as in the headless walkthrough below, run it in a window, and commit when it closes:

```
mkdir -p ~/vms
terrarium run Fedora-Cloud --provision cloud-init \
  --memory 2048 --cpus 2 \
  --commit-on-stop ~/vms/fedora
```

1. The window shows the guest booting. Once it is up, make the changes you want to keep.
2. Close the window (or `terrarium stop`). `--commit-on-stop` saves `~/vms/fedora-HASH.overlay`, with the helper and your changes; if the guest wrote to its disk and you gave no `--commit-on-stop`, closing asks first.
3. Continue from it, again in a window:

```
terrarium run Fedora-Cloud \
  --overlay ~/vms/fedora-HASH.overlay \
  --commit-on-stop ~/vms/fedora2
```

4. Your changes are already there. The saved overlay is never written to; this run's changes go to a copy, and are kept as `~/vms/fedora2-HASH.overlay` because of `--commit-on-stop`. Leave that flag off to discard them.

**Headless.** Fedora's cloud image takes the same steps as Debian's. It is a qcow2, which `terrarium pull` converts to a raw disk:

```
mkdir -p ~/vms
base=https://download.fedoraproject.org/pub/fedora/linux
base=$base/releases/45/Cloud/aarch64/images
terrarium pull \
  $base/Fedora-Cloud-Base-Generic-45-1.4.aarch64.qcow2
id=$(terrarium start Fedora-Cloud \
       --provision cloud-init \
       --memory 2048 --cpus 2)
terrarium wait
terrarium exec cat /etc/fedora-release
overlay=$(terrarium commit $id ~/vms/fedora)
terrarium stop $id
terrarium start Fedora-Cloud --overlay $overlay
```

The helper runs as root there too, and the overlay already has it.

## Ubuntu Linux

**Interactive, ephemeral.** Ubuntu's desktop ISO (the ARM64 one) boots to a GNOME live session; the VM's changes are discarded when it stops (only the pulled image stays in the store):

```
base=https://cdimage.ubuntu.com/releases/26.04/release
terrarium pull $base/ubuntu-26.04.1-desktop-arm64.iso
terrarium run ubuntu-26.04
```

It reaches the installer's *Welcome to Ubuntu* window after about a minute and a half. Close it to use the live session. Everything in the session is discarded when you close the window; terrarium has no recipe that installs Ubuntu onto a disk. The image has no helper, so `terrarium exec` is not available (the headless example below adds one); `terrarium shot`, `terrarium click`, `terrarium type`, and `terrarium key` work.

*VM* > *Send Key* has the Ubuntu desktop's chords: *Terminal* (Ctrl+Alt+T), *Show All Apps* (Super+A), *Run Command* (Alt+F2), *Switch Window* (Alt+Tab), *Close Window* (Alt+F4), *Screen Capture* (Shift+Ctrl+Alt+R), *Log Out* (Ctrl+Alt+Delete), and a *Switch Console* submenu (Ctrl+Alt+F3 to F6 are text logins; F1 is the login screen and F2 the session).

**Headless.** The same image runs without a window. `--provision cloud-init` gives the session a helper, which runs as root, and `--tweak ubuntu-no-welcome` closes the *Welcome* window, so `terrarium shot` shows the desktop; `start` returns once the tweak has run:

```
id=$(terrarium start ubuntu-26.04 --provision cloud-init \
       --tweak ubuntu-no-welcome \
       --memory 6144 --cpus 4)
terrarium wait
terrarium exec cat /etc/os-release
terrarium shot > screen.png
terrarium stop $id
```

1. `--memory` (MiB) and `--cpus` size the VM; the defaults are 4 GiB and up to 4 CPUs, so they are optional.
2. The *Welcome* window opens at every boot, so pass `--tweak ubuntu-no-welcome` each time. The tweak succeeds once it has closed the window, or after 50 seconds if the window never opened; it refuses a guest that is not an Ubuntu live session.
