# Distributions

Images that `terrarium pull` can fetch from a URL, for the Mac's own architecture (aarch64), each with how far terrarium has driven it. [AGENTS.md](../AGENTS.md) holds the requirements, the [README](../README.md#guides) lists the walkthroughs, and [tweaks.md](tweaks.md) the tweak catalog. Every image URL below answered a `HEAD` request with HTTP 200 on @DATE@. Documentation pages that block automated clients (DistroWatch, SourceForge, and Microsoft) were read in a fetch tool or a browser, not checked that way; [Sources](#sources) lists where each family's links come from.

## Recipes

| Image | Recipe |
|---|---|
| Alpine live ISO (standard, virt) | `--provision alpine` gives the helper; `--install alpine` installs to a disk |
| Cloud image with cloud-init (Alpine `cloudinit`, Debian `genericcloud` and `generic`, Fedora Cloud, Ubuntu cloud images, Rocky, AlmaLinux, and CentOS Stream `GenericCloud`, openSUSE `Cloud`) | `--provision cloud-init`, on systemd or OpenRC |
| Ubuntu desktop live ISO | `--provision cloud-init` |
| Debian `nocloud` images | `--provision nocloud`, which types the first-boot wizard's answers and a login |
| Any other live or installer ISO | none: boot it, then drive it with `shot`, `click`, `type`, and `key` (no helper, so no `exec`) |
| FreeBSD, OpenBSD, NetBSD | none: the helper supports Linux, macOS, and Windows only |
| macOS IPSW | `--install macos --user NAME --accept-license` |
| Windows ISO | `--install windows` |

`--provision` takes a live or cloud image and `--install` an installer; `--accept-license` is your agreement to the vendor's license, given per install. The recipes are described in [core/README.md](../core/README.md#recipes), and the [tweaks](tweaks.md) (each for one OS) run through the helper, so they need one: from a recipe, or put in by hand.

## Status

* ✅ tested: terrarium booted it and drove it; the footnote says how far.
* ❌ tested, and does not work: the footnote says what ran and what happened.

An ISO marked ✅ was booted with 4 GiB and 4 CPUs, and a `shot` after two minutes showed its installer or desktop (a boot menu counts); nothing was installed, and there is no helper unless a recipe is named. Cloud images get `--provision cloud-init` and `exec`.
* ⬜ untested: the URL answers, and nothing else is claimed. A recipe is named only where it should apply, and that is a prediction.
* 🚫 no aarch64 build, or no stable URL; see the note.
* — not published for that release.

The mark belongs to one image, not to its distribution: a ✅ on Fedora's Cloud Base says nothing about its Workstation Live ISO. A link's text is the file's size.

Each column header carries a colored square for the use case it serves, and columns run from newest to oldest:

* 🟩 everyday: a current stable or long-term-support release.
* 🟧 bleeding edge: nightly, testing, and rolling builds, and the newest interim release.
* 🟫 falling behind: an older release, superseded or nearing the end of its support.

Where a distribution publishes no nightly or testing image, its 🟧 column shows — (and a note says why).

## Linux

The distributions below run in order of popularity, by [DistroWatch's page-hit ranking](https://distrowatch.com/dwres.php?resource=popularity) for the last 12 months (average hits per day, read on @RANKDATE@). DistroWatch says its figures "correlate neither to usage nor to quality" (see the footnote on the rank column): the ranking counts visits to a distribution's page on that one site, so it favors enthusiast desktops, and CachyOS tops Ubuntu. The rank is DistroWatch's own, so the gaps are distributions this page does not cover, and one that DistroWatch does not rank sits at the end of the list. The last column is the best status of any aarch64 image of that distribution.

@INDEX@

[^distrowatch]: DistroWatch, [Page Hit Ranking](https://distrowatch.com/dwres.php?resource=popularity), the "Last 12 months" table, read @RANKDATE@; each rank links that distribution's own DistroWatch page. The figure is average hits per day, counting one hit per IP address per day on a distribution's page. DistroWatch states: "They correlate neither to usage nor to quality and should not be used to measure the market share of distributions." It lists CentOS Stream as "CentOS", and Arch Linux ARM stands in here for "Arch".

### CachyOS

🚫 No aarch64 build. [The download page](https://cachyos.org/download/) offers x86_64 desktop and handheld ISOs only, and an ARM request is open as [CachyOS/distribution#506](https://github.com/CachyOS/distribution/issues/506).

### Linux Mint

🚫 No aarch64 build. [The kernel.org mirror](https://mirrors.kernel.org/linuxmint/) lists only `64bit` (x86_64) ISOs for Mint 22.3 (Cinnamon, MATE, and Xfce) and LMDE 7, in `stable/`, `testing/`, and `debian/`.

### MX Linux

🚫 No generic aarch64 image. [The SourceForge listing](https://sourceforge.net/projects/mx-linux/files/Final/Xfce/) for MX 25.3 (Xfce, KDE, Fluxbox, and Xfce AHS) holds only `x64` ISOs, plus a Raspberry Pi respin (`mx25.3_rpi_respin_arm64.zip`, 2.6 GB) that is board-specific.

### Debian

Stable 13 (trixie), oldstable 12 (bookworm), 11 (bullseye, a Long Term Support series), and testing (forky, 14) from its daily and weekly builds.

@DEBIAN@

[^debian-cloud]: `genericcloud` 13 tested: `--provision cloud-init`, then `exec` as root, `commit`, and a restart from the overlay without `--provision`. That run used the image's `.raw` file (3.22 GB, same disk); `pull` converts a qcow2 in-process, which was tested on Fedora and Alpine images. `genericcloud` 12 tested straight from the qcow2 here: `--provision cloud-init`, then `exec` as root. `generic` 13 tested the same way. `generic` has a full kernel and `genericcloud` a smaller one for virtual machines. 11 tested the same way (both cloud images show a black screen and no helper in 200 s, and no DHCP lease appears in 75 s, so the guest does not come up: ❌; the 11.11.0 netinst ISO boots to the GRUB installer menu), and so did `generic` 12.
[^debian-testing]: Testing is the next stable release (forky, 14). Its cloud images are daily builds under `images/cloud/forky/daily/latest/`, and its ISOs are weekly builds; the names are stable. A `trixie/daily/latest` cloud image also exists, for the next 13 point release (not listed). Tested: both forky cloud images (`--provision cloud-init`, then `exec` as root; Debian GNU/Linux forky/sid) and the netinst ISO (GRUB installer menu). The weekly live GNOME ISO boots to its menu, but it is an old build, not testing's: the menu says "Debian GNU/Linux none (trixie)", built 2024-09-02, at 800x600.
[^debian-nocloud]: `nocloud` has no cloud-init (it signs in as root without a password), so `--provision cloud-init` cannot give it the helper; put the helper in by hand. 13 tested with `--provision nocloud`, which types the answers to systemd's first-boot wizard ("Please configure your system! -- Press any key to proceed --", then a timezone and root's password) and a root login over VNC, and installs the helper from a volume: `exec` as root about 100 s after the start, and after `commit` a restart from the overlay with no `--provision` answered in 11 s. `--provision cloud-init` alone gives no helper (the wizard waits for a key). 12 works the same way (`exec` as root). forky does not: its console is already at a login prompt, with no first-boot wizard, so the typed answers land at the login (❌). 11 does not boot, like its other cloud images (❌).
[^debian-installer]: Installers, with no recipe: drive them with `shot`, `click`, `type`, and `key`. The `current` path changes at each point release (13.7.0 today), and 12.15.0 and 11.11.0 sit in the archive. The archive has no arm64 DVD for 11.
[^debian-live]: Debian publishes an arm64 live ISO only as a weekly testing GNOME build. The [`current-live`](https://cdimage.debian.org/debian-cd/current-live/), [`12.15.0-live`](https://cdimage.debian.org/cdimage/archive/12.15.0-live/), and [`11.11.0-live`](https://cdimage.debian.org/cdimage/archive/11.11.0-live/) directories list only `amd64` (and `i386` and `source`), so the live ISOs for GNOME, KDE, Xfce, Cinnamon, MATE, LXDE, and LXQt are amd64 only.

### Pop!_OS

System76 publishes arm64 live ISOs for 24.04 LTS only[^pop]:

@POP@

[^pop]: Source: [System76's download page](https://system76.com/pop/download) and its build API, `https://api.pop-os.org/builds/24.04/generic?arch=arm64` (a `GET`; it answers with the ISO's URL, size, and SHA-256). System76 builds these for ARM hardware (the Thelio Astra, and devices that Tow-Boot supports). The generic ISO is a UEFI live image and may boot in a VM; untested. The NVIDIA ISO targets NVIDIA GPUs, which a VM lacks. There is no 22.04 arm64 build.

### Zorin OS

🚫 No aarch64 build. [The download page](https://zorin.com/os/download/) offers Zorin OS 18.1 (Core, Pro, and Education) with no Arm option, and [its requirements](https://help.zorin.com/docs/getting-started/system-requirements/) ask for an Intel or AMD 64-bit processor.

### Fedora

Releases 45, 44, and 43, and Rawhide, the nightly. Fedora has no LTS; each release is supported for about a year. Paths are on `download.fedoraproject.org`, which redirects to a mirror.

@FEDORA@

CoreOS (stable stream, `applehv` build for Apple's Virtualization framework): @COREOS@ [^fedora-coreos]

Not built for aarch64 in any of these releases: 🚫 the MATE, Cinnamon, Budgie, LXDE, and Sway live spins and Budgie Atomic. Sericea and Sway Atomic publish OCI archives, which are not bootable disks.

Each live spin also has a pre-installed `-Disk-` `.raw.xz` next to its ISO under `images/`; only the Workstation and KDE Plasma ones are listed.

[^fedora-rawhide]: Rawhide is Fedora's nightly. Its file names carry the compose date (`@COMPOSE@` here) and there is no `latest` alias, so these links work for about a day. To pull a later one, read [`development/rawhide/COMPOSE_ID`](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/COMPOSE_ID) and put its date in the name (`Fedora-Rawhide-YYYYMMDD.n.0` becomes `Rawhide-YYYYMMDD.n.0`). Rawhide has no MiracleWM or IoT images, and its Labs images were not checked. Tested on 2026-11-08 (Fedora 46 prerelease): the Cloud Base, UKI, and AmazonEC2 images with `--provision cloud-init`, then `exec` as root; the Workstation, KDE Plasma, Xfce, LXQt, i3, COSMIC, KDE Mobile, and SoaS live ISOs and the Server and Everything netinst ISOs and the Silverblue, Kinoite, and COSMIC Atomic installers each reached their session or first screen after 200 s. The Minimal and Server Guest disks gave no helper in 200 s (❌, as for 45). The disks, Disk images, and DVD were not tested.
[^fedora-live]: 44 tested: a GNOME session driven with `click`, `scroll`, `drag`, `type`, and `key`, and the Linux Send Key chords. The welcome screen appears after about 100 s with 4 GiB and 4 CPUs. The image has no helper and no recipe, so there is no `exec`. 45 tested too (a `shot` after two minutes): the Workstation, KDE Plasma, Xfce, LXQt, i3, COSMIC, KDE Mobile, SoaS, Python Classroom, and MiracleWM live ISOs each reached their session or first-run screen (i3 asks whether to generate its config, SoaS asks for a name, MiracleWM shows its DMS welcome), and the Silverblue, Kinoite, and COSMIC Atomic installers reached Anaconda's welcome page (after more than 140 s). Nothing was driven further. The 44 and 43 spins and installers tested the same way (the Kinoite, Silverblue, and COSMIC Atomic `ostree` ISOs reach Anaconda's welcome page too); so did the 43 Workstation ISO.
[^fedora-cloud]: Cloud Base 45 tested: `--provision cloud-init`, then `exec` as root, checked again on 2026-11-08 after the OpenRC change to that recipe. 44 was tested earlier with its AmazonEC2 `raw.xz` (`--provision cloud-init`, `exec`, `commit`, and a restart from the overlay). The 45 UKI qcow2 and AmazonEC2 `raw.xz` tested the same way (`exec` as root). The 44 and 43 qcow2 files are untested.
[^fedora-minimal]: 44 tested only as far as booting, taking a DHCP lease, answering ping, and working console and input. The image has no recipe, so put the helper in by hand to use `exec`.
[^fedora-installer]: Installers, with no recipe: Server netinst and DVD, and Everything netinst. Drive them with `shot`, `click`, `type`, and `key`. The 45 Server and Everything netinst ISOs boot to Anaconda's welcome screen. The Server Guest qcow2 is a prebuilt guest: 45 tested with `--provision cloud-init`, and `exec` never answered in 200 s; its console sat at the initial-setup prompt ("Please make a selection from the above ['c' to continue…]"), so the guest waits for an answer before the helper starts. The same wizard is on the display (root password and user creation unset), so `type` and `key` can answer it. 44 and 43 stop at it too, and so does Fedora Minimal 43.
[^fedora-atomic]: Installer ISOs, with no recipe. The 45 files are named `Installer`; the 44 and 43 ones `ostree`. 45 also publishes ready-made `Disk` and `QCOW` images for Silverblue and Kinoite, not listed here.
[^fedora-iot]: The IoT URLs carry the build date and change when a new build is published. 44 and 43 the same, and 45 tested: `--provision cloud-init` started, and `exec` never answered in 200 s. It boots to a login prompt ("Ignition: no config provided by user") with no account to log in to. The others are untested.
[^fedora-coreos]: CoreOS provisions with Ignition, not cloud-init, so neither `--provision cloud-init` nor `--provision alpine` applies. The URL carries the build ID (44.20261023.3.1) and changes with each stable build. Tested: `--provision cloud-init` started, and `exec` never answered in 200 s. It does not boot: its Ignition tries to fetch the config from the host over vsock port 1024 (Podman's applehv arrangement), gets "connection reset by peer", and drops to emergency mode, so serving a config on that port would be a feature.

### EndeavourOS

🚫 No generic aarch64 image. [The ISO mirror](https://mirror.alpix.eu/endeavouros/iso/) lists no Arm ISO, and [the Arm project](https://github.com/endeavouros-arm/images/releases) publishes images for the Raspberry Pi 4 and 5, ODROID-N2, and Pinebook Pro only.

### Ubuntu

Long-term support (LTS) releases 22.04, 24.04, and 26.04, and the current release, 26.10.

@UBUNTU@

The official flavors have no arm64 build on cdimage.ubuntu.com, for any of these releases: 🚫 Kubuntu, Lubuntu, Xubuntu, Ubuntu MATE, Ubuntu Budgie, Ubuntu Cinnamon, Ubuntu Unity, Ubuntu Studio, and Ubuntu Kylin. Edubuntu publishes only a Raspberry Pi image, which is no use as a generic EFI guest.

Ubuntu Core (26, 24, and 22) is not listed: it does not boot under Virtualization. Its initramfs fails (`snap-bootstrap` finds no TPM2 device and no model assertion in `ubuntu-boot`) and drops to emergency mode, and 24 loops through an emergency reboot.

[^ubuntu-desktop]: 26.04.1 tested: `--provision cloud-init` gives the live session its helper (it runs as root), and `--tweak ubuntu-no-welcome` closes the installer's *Welcome to Ubuntu* window, which appears about a minute and a half in. `exec`, `shot`, `key`, the Linux Send Key chords, and the F1 to F6 consoles all worked. Without provisioning it boots at the default memory and the Welcome window stays. 24.04 and 26.10 are untested; the same recipe is expected to apply. 22.04 has no arm64 desktop ISO.
[^ubuntu-daily]: There is no Ubuntu nightly to pull yet. The 26.10 column was tested on 2026-11-08: the desktop ISO reaches its welcome window, the live server ISO its language screen, and the preinstalled server, cloud, and minimal cloud images answer `exec` as root after `--provision cloud-init` (Ubuntu 26.10). [`cdimage.ubuntu.com/ubuntu/`](https://cdimage.ubuntu.com/ubuntu/) lists only `noble`, `resolute`, and `stonking`, and the `stonking` daily ISO has the same size and timestamp as the 26.10 release ISO, so the 27.04 development series has no daily images. This column fills in when its codename directory appears.
[^ubuntu-installer]: No recipe installs Ubuntu onto a disk. Boot the live-server ISO and drive the installer with `shot`, `click`, `type`, and `key`. The preinstalled server images are generic `.xz` raw disks: 26.04.1 carries cloud-init (`--provision cloud-init`, then `exec` as root). 26.04.1's live server ISO boots to the installer's language screen. 22.04.5 also publishes a `+largemem` live-server ISO with a 64k-page kernel, not listed here.
[^ubuntu-cloud]: These images ship cloud-init (NoCloud), so `--provision cloud-init` gives them the helper, as it does for Debian and Fedora cloud images: tested on the 24.04, 26.04, and minimal 26.04 images (`exec` as root). The 22.04 cloud image and the 24.04 minimal cloud and preinstalled server images tested the same way, and the 24.04 desktop and live server ISOs and the 22.04 live server ISO reach their welcome window or language screen. 22.04 has no minimal arm64 image.

### Manjaro

🚫 No aarch64 build of the mainline edition. [The mainline downloads](https://manjaro.org/products/download/x86) are x86; its ARM edition is a separate product that was not checked.

### Bazzite

🚫 No aarch64 build. [bazzite.gg](https://bazzite.gg) says it is for x86 handhelds. Apple silicon support is an open pull request, [ublue-os/bazzite#2155](https://github.com/ublue-os/bazzite/pull/2155).

### Arch Linux ARM

🚫 No ISO or disk image. [The generic aarch64 page](https://archlinuxarm.org/platforms/armv8/generic) offers a root filesystem tarball, so you build the disk yourself. (Arch Linux itself is x86_64 only.)

### openSUSE

Leap 16.1, 16.0, and 15.6, and Tumbleweed.

@SUSE@

Leap 16 has the Agama installers only; its live desktops exist for Tumbleweed. The `64kb`, real-time, and encrypted image variants also exist, and are not listed. The `efi` ARM images target generic UEFI. Tumbleweed's JeOS takes `--provision cloud-init` (`exec` as root). Leap 15.6's JeOS crashes about 35 s into its boot (a kernel oops from an undefined instruction in `btrfs_compress_heuristic`), after which `exec` waits forever on the dead guest (❌). The KDE, GNOME, and XFCE ones boot to a login screen with no helper (✅ as a boot).

[^suse-installer]: Installers, with no recipe: drive them with `shot`, `click`, `type`, and `key`. The Leap 16 online installer sits in the `offline/` directory. The Leap 16.0 installers reach Agama's product page (Leap 16.0 and Leap Micro 6.2, the offline one), and Leap 15.6's NET ISO reaches YaST's license page. Leap 16.1's online and offline installers boot to Agama's *Select a mode* page.
[^suse-kvm]: The Minimal-VM `kvm` images boot UEFI and configure themselves with combustion or Ignition, not cloud-init. That comes from memory of openSUSE's image definitions; the images were not opened. Leap 16.1 and Tumbleweed tested: `--provision cloud-init` started, and `exec` never answered in 200 s. Leap 16.1, 16.0, and 15.6 wait at their JeOS Firstboot dialog (*Welcome to openSUSE Leap 16.1!*, with a Start button) on the display.
[^suse-cloud]: @SUSECLOUD@

Atomic (transactional) editions:

@ATOMIC@

[^suse-atomic]: Leap Micro and MicroOS configure at first boot with Ignition or combustion. MicroOS tested: the OpenStack Cloud qcow2 with `--provision cloud-init`, then `exec` as root (openSUSE MicroOS); the kvm-and-xen qcow2 gave no helper in 200 s. The Leap Micro 6.2 ISO tested: `start` returned, and the VM stopped by itself within a second or two, with empty serve and console logs (cause not found: the ISO has no El Torito boot record, no MBR, and no GPT, so nothing in it can boot as a disk; `start` now fails with "the guest stopped itself", as it does for the Oracle 8 ISO). The Leap Micro 6.2 qcow2 tested nonetheless: `--provision cloud-init`, then `exec` as root (openSUSE Leap Micro 6.2). The others are untested.

🚫 Slowroll has x86_64 images only ([its ISO listing](https://download.opensuse.org/slowroll/iso/)), and Aeon and Kalpa have no aarch64 files in [the Tumbleweed ports listing](https://download.opensuse.org/ports/aarch64/tumbleweed/iso/).

### Nobara

🚫 No aarch64 build. [The download page](https://nobaraproject.org/download-nobara/) lists only the `Nobara-44-*.iso` files, which are x86_64.

### NixOS

@FLAT:NixOS@

### elementary OS

🚫 No stable URL. elementary OS 8.1 publishes an arm64 ISO, but the download link on [elementary.io](https://elementary.io/) carries a timestamp token, so there is nothing stable to pull. Take it from the page.

### Void Linux

@FLAT:Void Linux@

[^void]: Void's newest aarch64 live build is older than its x86_64 ones. Both ISOs tested: the base one boots to a text login (`root` and `anon`, password `voidlinux`), and the Xfce one to a logged-in Xfce desktop. The Asahi ISO is for Apple silicon hardware, not a VM.

### Alpine

3.24 and 3.23, from `dl-cdn.alpinelinux.org`. The [cloud images](https://alpinelinux.org/cloud/) come in `cloudinit` and `tiny` variants.

@ALPINE@

[^alpine-edge]: Alpine's [`edge` aarch64 directory](https://dl-cdn.alpinelinux.org/alpine/edge/releases/aarch64/) holds no ISOs or cloud images, only netboot and minirootfs tarballs last built 2026-08-05, so there is nothing to pull as a VM.
[^alpine-live]: Standard 3.24.4 tested: `--provision alpine` gives the live session the helper, so `exec` works (sign in as `root`, no password). `--install alpine` to a disk, the `linux/no-blank` and `linux/alpine-repositories` tweaks, and `commit` were tested on 3.24.3. The virt ISO 3.24.4 and the 3.23.8 standard and virt ISOs tested only as far as booting to the console login prompt; they have no helper. The 3.23 cloud image tested like 3.24: `--provision cloud-init` (OpenRC), then `exec` as root.
[^alpine-cloud]: The `cloudinit` variant of 3.24.4 tested: `--provision cloud-init` (the OpenRC path), `exec` as root, `commit`, and a restart from the overlay without `--provision` in about 20 s. The image's own login user is `alpine`. The 3.23 files carry `uefi` in their names and are untested.
[^alpine-tiny]: `tiny` images bootstrap with Tiny Cloud, which `--provision cloud-init` does not drive; put the helper in by hand. 3.24.4 and 3.23.8 tested: `--provision cloud-init` started, and `exec` never answered in 200 s. It boots fully to a login prompt (Tiny Cloud reports `Unknown Cloud 'unknown'` and finds no user data), so only the helper is missing.

### Kali Linux

@FLAT:Kali Linux@

[^kali]: The tar holds a disk image and ships cloud-init; `pull` takes a tar of one file, so check that it holds exactly one. Tested: `pull` took the tar, `--provision cloud-init`, then `exec` as root (Kali GNU/Linux Rolling). The live ISO is published only as a torrent. Kali's arm64 VM images for VMware, QEMU, and UTM do not exist, and its ARM images are for boards.
[^kali-weekly]: The names carry the ISO week (`2026-W46`) and the directory holds the latest two, with no `latest` alias, so these links last about a week. Weekly builds are installers only; there are no arm64 live or cloud images in `kali-weekly/`. Both tested: the GRUB installer menu.

### Tails

🚫 No aarch64 build. [Its requirements](https://tails.net/doc/about/requirements/index.en.html) say it needs an x86-64 processor and does not work on ARM.

### Solus

🚫 No aarch64 build. [The download page](https://getsol.us/download/) states a 64-bit x86-64 processor.

### Parrot OS

@FLAT:Parrot OS@

### AlmaLinux

@ALMA@

AlmaLinux 10 publishes only GNOME and KDE live ISOs; MATE, Xfce, and GNOME-Mini exist for 9 only. OpenNebula images also exist, and are not listed.

Enterprise Linux 8 (AlmaLinux 8.10, Rocky 8.10, and Oracle Linux 8) is not listed: none of its images boots under Virtualization. All eleven that were tested failed (the ISOs, the cloud images, and Oracle's `kvm` image); the DVDs, which use the same GRUB, were not tried. On the Rocky 8.10 ISO GRUB itself, before its menu, prints `Invalid call efi_update_mem_attrs ... addr is not page aligned` and hangs (a keypress does nothing); AlmaLinux 8.10 stays black; Oracle 8's ISO makes the VM stop at once, and its cloud images show a black screen.

[^alma-kitten]: AlmaLinux Kitten is the development release, built from CentOS Stream; its `latest` names are stable aliases. Kitten has no MATE or Xfce live ISO. @KITTEN@
[^el-installer]: Installers (Anaconda), with no recipe: drive them with `shot`, `click`, `type`, and `key`. The EL9 and EL10 ISOs boot to Anaconda's welcome page.
[^alma-live]: Live ISOs boot to a desktop; there is no recipe and no helper.
[^el-cloud]: @ELCLOUD@

### CentOS Stream

@CENTOS@

[^centos-ec2]: A raw disk built for AWS, compressed with xz; same cloud-init arrangement as the qcow2. The 9 image tested: `--provision cloud-init`, then `exec` as root.

### Gentoo

@FLAT:Gentoo@

[^gentoo]: The URLs carry the build stamp and change with each autobuild. The minimal ISO is Gentoo's generic arm64 install image; it boots under Virtualization to a root console (`livecd`, automatic login) with no helper. The qcow2 images are prebuilt disks; the `cloud-init` one carries cloud-init, and tested: `--provision cloud-init`, then `exec` as root. The `console` one tested: `exec` never answered in 200 s.

### Slackware

🚫 No aarch64 build of mainline Slackware. [The mirror](https://mirrors.slackware.com/slackware/) has only `slackware` and `slackware64` trees; Slackware ARM is a separate port that was not checked.

### Rocky Linux

@ROCKY@

EC2, OCP, and Raspberry Pi images also exist, and are not listed. Rocky 8.10 is not listed; see [the AlmaLinux note](#almalinux) on Enterprise Linux 8.

[^rocky-staging]: A public staging tree (`dl.rockylinux.org/stg/rocky/10.3`) with `latest` aliases for the unreleased 10.3, not an official nightly channel. Tested: GenericCloud-Base and LVM (`--provision cloud-init`, then `exec` as root; Rocky Linux 10.3) and the boot and minimal ISOs (Anaconda's welcome page, marked "pre-release / testing").

### Deepin

@FLAT:Deepin@

[^deepin]: From the release directory's listing; the ISO targets arm64 PCs; it boots under Virtualization to its boot menu (1920x1080), and went no further.

### Qubes OS

🚫 No aarch64 build. [The downloads page](https://www.qubes-os.org/downloads/) offers only `Qubes-R4.3.2-x86_64.iso`.

### Oracle Linux

@ORACLE@

[^oracle]: Downloads are anonymous. The ISOs are the newest updates (10 U2, 9 U8); the templates lag them (10 U1, 9 U8). Oracle Linux 8 is not listed; see [the AlmaLinux note](#almalinux) on Enterprise Linux 8. `kvm-cloud` carries cloud-init (the OL9 U8 image's README lists `cloud-init`), and `kvm` is the non-cloud image, which boots UEFI. UTM `.utm.zip` bundles also exist; `pull` does not take a zip, so they are not listed. 10 `kvm-cloud` and `kvm` tested: `--provision cloud-init`, then `exec` as root, on both (Oracle Linux Server 10.1); the plain `kvm` image answered too. The rest are untested.

### Amazon Linux 2023

DistroWatch does not rank Amazon Linux.

@AMAZON@ (`kvm-arm64` qcow2)[^amazon]

[^amazon]: There is no ISO. The `os-images/` directory itself returns 403, but the files download anonymously from `latest/kvm-arm64/`, and the file name carries the build date. The image has no usable login until it is seeded; AWS's [guide to running it outside EC2](https://docs.aws.amazon.com/linux/al2023/ug/outside-ec2.html) supplies NoCloud seed data, which is what `--provision cloud-init` attaches. Tested: `--provision cloud-init`, then `exec` as root (Amazon Linux 2023.12.20261102).

## BSDs

FreeBSD, OpenBSD, and NetBSD publish generic aarch64 images that should boot under Virtualization's UEFI, listed in the same DistroWatch order. terrarium's helper supports Linux, macOS, and Windows, so none of these has a helper: `--provision cloud-init` installs the Linux helper and does not apply. Drive them with `shot`, `click`, `type`, and `key`.

@BSD@

[^freebsd]: The `BASIC-CLOUDINIT` images use FreeBSD's `nuageinit`, not Python cloud-init, and have no default password; login comes from injected user-data or SSH keys. The plain VM images sign in as `root` with an empty password and run no sshd. FreeBSD 15.2 is in beta, and snapshots follow `Latest/` paths. The `.xz` files are single compressed disks, which `pull` decompresses. Tested on 15.1 with no helper (there is none for BSD): the cloud-init image's `--provision cloud-init` gave no `exec`, as expected, and the console log stayed empty. The plain VM image reached FreeBSD's boot menu and stopped at "Loading kernel" on the display after two minutes (the kernel may write to a serial console only). Every FreeBSD image tested (15.1, 14.5, 15.2-BETA1, and 16.0-CURRENT; ISOs, plain VM images, and cloud-init images) was left running two to eleven minutes, and none got past the loader: the 15.1 plain VM image still had not finished loading the kernel after 11 minutes (its `text=` and `data=` progress line crawls, about 21 KB/s, far slower than other guests read the same disk), and the 14.5 cloud-init image reached "Loading configured modules" and printed `can't find '/boot/entropy'` after 10 minutes. With four vCPUs the cause of the crawl was not found, but with `--cpus 1` the 15.1 plain VM image got through the loader in under three minutes and stopped at `No valid device tree blob found!`: VZ's firmware offers ACPI only, and 15.x needs a device tree, as [tjfontaine/freebsd-apple-virtualization](https://github.com/tjfontaine/freebsd-apple-virtualization) found (it boots a prepared 16.0-CURRENT guest with one vCPU, one console, and no USB keyboard or pointer, which terrarium cannot yet give a guest). The 16.0-CURRENT cloud-init image was still loading its kernel after ten minutes with one vCPU. The dvd1 ISO and the 14.5 ISOs not named here are untested.
[^openbsd]: Installers: set the root password during the install. The 8.0 install ISO reaches the same installation program prompt as the miniroot. There are no cloud-init images. The 8.0 miniroot tested: it boots to the installation program's `(I)nstall, (U)pgrade, (A)utoinstall or (S)hell?` prompt on the display.
[^netbsd]: There is no cloud-init. The prebuilt `arm64.img.gz` is a ready-to-boot disk, not an installer (a `gzip`, not `xz`, file; `pull` decompresses both), and the `.iso` and `-install.img.gz` are installers. Tested, not marked: the prebuilt disk booted to NetBSD's efiboot and printed "booting netbsd", and the ISO to its installation CD menu, "loading ramdisk.fs"; both screens stopped there after two minutes (the kernel may write to a serial console only).

## macOS

Restore images (IPSW) for the virtual Mac, from [ipsw.me](https://api.ipsw.me/v4/device/VirtualMac2,1?type=ipsw), which lists 60 of them from 12.4 to 27.2. This table keeps the newest of each major version, plus 27.0 and 26.0. All are on `updates.cdn-apple.com` and answered HTTP 200.

@MAC@

27.2 tested: `--install macos --user NAME --accept-license` (the helper goes in over SSH), `exec`, `shot`, `click`, and the macOS Send Key chords. [^macos]

[^macos-beta]: ipsw.me lists release builds only, and no beta or seed IPSW has a URL that can be pulled without an Apple developer account. Untested.
[^macos]: Recipe `--install macos`; tweaks `macos/no-sleep`, `macos/no-screensaver`, and `macos/quiet-setup`. The other versions are untested, including whether Virtualization on a macOS 27 host accepts each guest. ipsw.me's `signed` flag is false for every entry, so it does not say which images Apple still signs; the CDN serves them all.

## Windows

Microsoft publishes no stable URL for an ARM64 image. The download page makes a link that lives about 24 hours, so save the ISO and `pull` the file, as the [Windows guide](windows.md) does. The page offers only the current release (26H2 on 2026-11-08), as one multi-edition ISO in each language; older builds are not offered.

| Release | Where to get it | Status |
|---|---|---|
| Windows 11 ARM64, build 26300 | [The ARM64 download page](https://www.microsoft.com/en-us/software-download/windows11arm64) | ✅ `pull` of the saved ISO, then `--install windows`[^windows] |
| Windows 11 Enterprise evaluation | [The evaluation center](https://www.microsoft.com/en-us/evalcenter/download-windows-11-enterprise) | 🚫 behind a registration form; an ARM64 ISO was not confirmed |
| Windows 10 ARM64 | none found | 🚫 |
| Windows Server 2022 and 2025 ARM64 | none found | 🚫 Microsoft is reported not to ship an ARM64 Server ISO |
| Windows Insider Preview ARM64 | [The Insider page](https://www.microsoft.com/en-us/software-download/windowsinsiderpreviewARM64) | 🚫 needs an Insider sign-in |

[^windows]: Build 26300 tested: `--install windows` (unattended install, the helper as an at-logon task), `commit --on-stop`, a boot of the saved guest with the ISO removed, `exec`, input through `key` and `type`, and the license page. Tweaks: `windows/edge-quiet`, `windows/no-sleep`, and `windows/no-lock`.

## Sources

Every image link above comes from the vendor's own download page, release directory, or API, found there on @DATE@ and checked with `HEAD`. Evidence for a missing aarch64 build is linked in that distribution's section. Statements marked as from memory (openSUSE's image definitions) were not checked.

* Popularity: DistroWatch's [Page Hit Ranking](https://distrowatch.com/dwres.php?resource=popularity).
* Ubuntu: [cdimage.ubuntu.com/releases](https://cdimage.ubuntu.com/releases/) and [/ubuntu](https://cdimage.ubuntu.com/ubuntu/), [cloud-images.ubuntu.com](https://cloud-images.ubuntu.com/), and [Ubuntu Core](https://cdimage.ubuntu.com/ubuntu-core/).
* Debian: [cdimage.debian.org](https://cdimage.debian.org/) (`debian-cd/current`, `cdimage/archive`, `cdimage/weekly-builds`, `cdimage/weekly-live-builds`, and `images/cloud`).
* Fedora: [dl.fedoraproject.org](https://dl.fedoraproject.org/pub/fedora/linux/) (`releases`, `development/rawhide`, and [`alt/iot`](https://dl.fedoraproject.org/pub/alt/iot/)), and the [CoreOS stable stream](https://builds.coreos.fedoraproject.org/streams/stable.json).
* Alpine: [dl-cdn.alpinelinux.org/alpine](https://dl-cdn.alpinelinux.org/alpine/) and the [cloud images page](https://alpinelinux.org/cloud/).
* Red Hat family: [Rocky](https://download.rockylinux.org/pub/rocky/) (and its [staging tree](https://dl.rockylinux.org/stg/rocky/)), [AlmaLinux](https://repo.almalinux.org/almalinux/) (and [Kitten](https://repo.almalinux.org/almalinux-kitten/10-kitten/)), CentOS Stream ([images](https://cloud.centos.org/centos/) and [ISOs](https://mirror.stream.centos.org/)), Oracle Linux ([ISOs](https://yum.oracle.com/oracle-linux-isos.html) and [templates](https://yum.oracle.com/oracle-linux-templates.html)), and Amazon Linux ([guide](https://docs.aws.amazon.com/linux/al2023/ug/outside-ec2.html)).
* openSUSE: [Leap](https://download.opensuse.org/distribution/leap/), [Leap Micro](https://download.opensuse.org/distribution/leap-micro/6.2/), and [Tumbleweed and MicroOS for aarch64](https://download.opensuse.org/ports/aarch64/tumbleweed/).
* Others: [Kali](https://cdimage.kali.org/) and its [cloud images](https://kali.download/cloud-images/), [NixOS](https://channels.nixos.org/), [Gentoo](https://distfiles.gentoo.org/releases/arm64/autobuilds/), [Void](https://repo-default.voidlinux.org/live/current/), [Parrot](https://deb.parrot.sh/parrot/iso/), [Deepin](https://cdimage.deepin.com/releases/25.2.0/arm64/), and [Pop!_OS](https://system76.com/pop/download).
* BSDs: [FreeBSD](https://download.freebsd.org/releases/VM-IMAGES/) (and, for what Virtualization needs, [freebsd-apple-virtualization](https://github.com/tjfontaine/freebsd-apple-virtualization)), [OpenBSD](https://cdn.openbsd.org/pub/OpenBSD/8.0/arm64/), and [NetBSD](https://cdn.netbsd.org/pub/NetBSD/images/11.1/).
* macOS: the [ipsw.me API](https://api.ipsw.me/v4/device/VirtualMac2,1?type=ipsw) for the `VirtualMac2,1` model.
* Windows: Microsoft's [ARM64 download page](https://www.microsoft.com/en-us/software-download/windows11arm64), [evaluation center](https://www.microsoft.com/en-us/evalcenter/download-windows-11-enterprise), and [Insider page](https://www.microsoft.com/en-us/software-download/windowsinsiderpreviewARM64).
