# Distributions

Images that `terrarium pull` can fetch from a URL, for the Mac's own architecture (aarch64), each with how far terrarium has driven it. [AGENTS.md](../AGENTS.md) holds the requirements, the [README](../README.md#guides) lists the walkthroughs, and [tweaks.md](tweaks.md) the tweak catalog. Every image URL below answered a `HEAD` request with HTTP 200 on 2026-11-09. Documentation pages that block automated clients (DistroWatch, SourceForge, and Microsoft) were read in a fetch tool or a browser, not checked that way; [Sources](#sources) lists where each family's links come from.

## Recipes

| Image | Recipe |
|---|---|
| Alpine live ISO (standard, virt) | `--provision alpine` gives the helper; `--install alpine` installs to a disk |
| Cloud image with cloud-init (Alpine `cloudinit`, Debian `genericcloud` and `generic`, Fedora Cloud, Ubuntu cloud images, Rocky, AlmaLinux, and CentOS Stream `GenericCloud`, openSUSE `Cloud`) | `--provision cloud-init`, on systemd or OpenRC |
| Ubuntu desktop live ISO | `--provision cloud-init` |
| Debian `nocloud` images | `--provision nocloud`, which answers the first-boot wizard's questions as they appear on the screen, then logs in |
| openSUSE Minimal-VM `kvm`, MicroOS `kvm`, and Leap Micro images | `--provision combustion`, for images that configure themselves with Combustion, not cloud-init |
| Any other live or installer ISO | none: boot it, then drive it with `shot`, `click`, `type`, and `key` (no helper, so no `exec`) |
| FreeBSD, OpenBSD, NetBSD | none: the helper supports Linux, macOS, and Windows only |
| macOS IPSW | `--install macos --user NAME --accept-license` |
| Windows ISO | `--install windows` |

`--provision` takes a live or cloud image and `--install` an installer; `--accept-license` is your agreement to the vendor's license, given per install. The recipes are described in [core/README.md](../core/README.md#recipes), and the [tweaks](tweaks.md) (each for one OS) run through the helper, so they need one: from a recipe, or put in by hand. In the examples below, IMAGE (or a more specific name: CLOUD_IMAGE, ISO_IMAGE, and so on) is the name `terrarium images` lists after `terrarium pull URL`; each line suits the table rows its name describes.

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

The distributions below run in order of popularity, by [DistroWatch's page-hit ranking](https://distrowatch.com/dwres.php?resource=popularity) for the last 12 months (average hits per day, read on 2026-11-08). DistroWatch says its figures "correlate neither to usage nor to quality" (see the footnote on the rank column): the ranking counts visits to a distribution's page on that one site, so it favors enthusiast desktops, and CachyOS tops Ubuntu. The rank is DistroWatch's own, so the gaps are distributions this page does not cover, and one that DistroWatch does not rank sits at the end of the list. The last column is the best status of any aarch64 image of that distribution.

| Rank[^distrowatch] | Distribution | Hits per day | aarch64 |
|---|---|---|---|
| [1](https://distrowatch.com/cachyos) | [CachyOS](#cachyos) | 3219 | 🚫 |
| [2](https://distrowatch.com/mint) | [Linux Mint](#linux-mint) | 1967 | 🚫 |
| [3](https://distrowatch.com/mx) | [MX Linux](#mx-linux) | 1749 | 🚫 |
| [4](https://distrowatch.com/debian) | [Debian](#debian) | 1258 | ✅ |
| [5](https://distrowatch.com/popos) | [Pop!_OS](#pop_os) | 1248 | ✅ |
| [6](https://distrowatch.com/zorin) | [Zorin OS](#zorin-os) | 1144 | 🚫 |
| [7](https://distrowatch.com/fedora) | [Fedora](#fedora) | 1123 | ✅ |
| [8](https://distrowatch.com/endeavour) | [EndeavourOS](#endeavouros) | 981 | 🚫 |
| [9](https://distrowatch.com/ubuntu) | [Ubuntu](#ubuntu) | 951 | ✅ |
| [10](https://distrowatch.com/manjaro) | [Manjaro](#manjaro) | 893 | 🚫 |
| [11](https://distrowatch.com/bazzite) | [Bazzite](#bazzite) | 830 | 🚫 |
| [14](https://distrowatch.com/arch) | [Arch Linux ARM](#arch-linux-arm) | 633 | 🚫 |
| [15](https://distrowatch.com/opensuse) | [openSUSE](#opensuse) | 631 | ✅ |
| [17](https://distrowatch.com/nobara) | [Nobara](#nobara) | 552 | 🚫 |
| [20](https://distrowatch.com/nixos) | [NixOS](#nixos) | 500 | ✅ |
| [22](https://distrowatch.com/elementary) | [elementary OS](#elementary-os) | 450 | ✅ |
| [24](https://distrowatch.com/void) | [Void Linux](#void-linux) | 433 | ✅ |
| [30](https://distrowatch.com/alpine) | [Alpine](#alpine) | 341 | ✅ |
| [33](https://distrowatch.com/kali) | [Kali Linux](#kali-linux) | 324 | ✅ |
| [42](https://distrowatch.com/tails) | [Tails](#tails) | 293 | 🚫 |
| [45](https://distrowatch.com/solus) | [Solus](#solus) | 278 | 🚫 |
| [47](https://distrowatch.com/parrot) | [Parrot OS](#parrot-os) | 269 | ✅ |
| [51](https://distrowatch.com/alma) | [AlmaLinux](#almalinux) | 252 | ✅ |
| [52](https://distrowatch.com/centos) | [CentOS Stream](#centos-stream) | 250 | ✅ |
| [55](https://distrowatch.com/gentoo) | [Gentoo](#gentoo) | 235 | ✅ |
| [62](https://distrowatch.com/slackware) | [Slackware](#slackware) | 201 | 🚫 |
| [67](https://distrowatch.com/rocky) | [Rocky Linux](#rocky-linux) | 192 | ✅ |
| [76](https://distrowatch.com/deepin) | [Deepin](#deepin) | 184 | ✅ |
| [98](https://distrowatch.com/qubes) | [Qubes OS](#qubes-os) | 153 | 🚫 |
| [177](https://distrowatch.com/oracle) | [Oracle Linux](#oracle-linux) | 79 | ✅ |
| — | [Amazon Linux 2023](#amazon-linux-2023) | not ranked | ✅ |

[^distrowatch]: DistroWatch, [Page Hit Ranking](https://distrowatch.com/dwres.php?resource=popularity), the "Last 12 months" table, read 2026-11-08; each rank links that distribution's own DistroWatch page. The figure is average hits per day, counting one hit per IP address per day on a distribution's page. DistroWatch states: "They correlate neither to usage nor to quality and should not be used to measure the market share of distributions." It lists CentOS Stream as "CentOS", and Arch Linux ARM stands in here for "Arch".

### CachyOS

🚫 No aarch64 build. [The download page](https://cachyos.org/download/) offers x86_64 desktop and handheld ISOs only, and an ARM request is open as [CachyOS/distribution#506](https://github.com/CachyOS/distribution/issues/506).

### Linux Mint

🚫 No aarch64 build. [The kernel.org mirror](https://mirrors.kernel.org/linuxmint/) lists only `64bit` (x86_64) ISOs for Mint 22.3 (Cinnamon, MATE, and Xfce) and LMDE 7, in `stable/`, `testing/`, and `debian/`.

### MX Linux

🚫 No generic aarch64 image. [The SourceForge listing](https://sourceforge.net/projects/mx-linux/files/Final/Xfce/) for MX 25.3 (Xfce, KDE, Fluxbox, and Xfce AHS) holds only `x64` ISOs, plus a Raspberry Pi respin (`mx25.3_rpi_respin_arm64.zip`, 2.6 GB) that is board-specific.

### Debian

Stable 13 (trixie), oldstable 12 (bookworm), 11 (bullseye, a Long Term Support series), and testing (forky, 14) from its daily and weekly builds.

```
terrarium run CLOUD_IMAGE --provision cloud-init
terrarium run NOCLOUD_IMAGE --provision nocloud
terrarium run INSTALLER_IMAGE
```

| Variant | 🟧 testing / 14 forky[^debian-testing] | 🟩 13 trixie | 🟫 12 bookworm | 🟫 11 bullseye (LTS) |
|---|---|---|---|---|
| Cloud: genericcloud (qcow2)[^debian-cloud] | ✅ [0.35 GB](https://cdimage.debian.org/images/cloud/forky/daily/latest/debian-14-genericcloud-arm64-daily.qcow2) | ✅ [0.34 GB](https://cdimage.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-arm64.qcow2) | ✅ [0.35 GB](https://cdimage.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-arm64.qcow2) | ❌ [0.27 GB](https://cdimage.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-arm64.qcow2) |
| Cloud: generic (qcow2)[^debian-cloud] | ✅ [0.46 GB](https://cdimage.debian.org/images/cloud/forky/daily/latest/debian-14-generic-arm64-daily.qcow2) | ✅ [0.43 GB](https://cdimage.debian.org/images/cloud/trixie/latest/debian-13-generic-arm64.qcow2) | ✅ [0.44 GB](https://cdimage.debian.org/images/cloud/bookworm/latest/debian-12-generic-arm64.qcow2) | ❌ [0.33 GB](https://cdimage.debian.org/images/cloud/bullseye/latest/debian-11-generic-arm64.qcow2) |
| Cloud: nocloud (qcow2)[^debian-nocloud] | ✅ [0.44 GB](https://cdimage.debian.org/images/cloud/forky/daily/latest/debian-14-nocloud-arm64-daily.qcow2) | ✅ [0.40 GB](https://cdimage.debian.org/images/cloud/trixie/latest/debian-13-nocloud-arm64.qcow2) | ✅ [0.41 GB](https://cdimage.debian.org/images/cloud/bookworm/latest/debian-12-nocloud-arm64.qcow2) | ❌ [0.31 GB](https://cdimage.debian.org/images/cloud/bullseye/latest/debian-11-nocloud-arm64.qcow2) |
| Installer: netinst ISO[^debian-installer] | ✅ [0.98 GB](https://cdimage.debian.org/cdimage/weekly-builds/arm64/iso-cd/debian-testing-arm64-netinst.iso) | ✅ [0.74 GB](https://cdimage.debian.org/debian-cd/current/arm64/iso-cd/debian-13.7.0-arm64-netinst.iso) | ✅ [0.56 GB](https://cdimage.debian.org/cdimage/archive/12.15.0/arm64/iso-cd/debian-12.15.0-arm64-netinst.iso) | ✅ [0.35 GB](https://cdimage.debian.org/cdimage/archive/11.11.0/arm64/iso-cd/debian-11.11.0-arm64-netinst.iso) |
| Installer: DVD-1 ISO[^debian-installer] | ✅ [3.99 GB](https://cdimage.debian.org/cdimage/weekly-builds/arm64/iso-dvd/debian-testing-arm64-DVD-1.iso) | ✅ [3.99 GB](https://cdimage.debian.org/debian-cd/current/arm64/iso-dvd/debian-13.7.0-arm64-DVD-1.iso) | ✅ [3.99 GB](https://cdimage.debian.org/cdimage/archive/12.15.0/arm64/iso-dvd/debian-12.15.0-arm64-DVD-1.iso) | 🚫 |
| Live GNOME ISO[^debian-live] | ✅ [3.60 GB](https://cdimage.debian.org/cdimage/weekly-live-builds/arm64/iso-hybrid/debian-live-testing-arm64-gnome.iso) | 🚫 | 🚫 | 🚫 |

[^debian-cloud]: `genericcloud` 13 tested: `--provision cloud-init`, then `exec` as root, `commit`, and a restart from the overlay without `--provision`. That run used the image's `.raw` file (3.22 GB, same disk); `pull` converts a qcow2 in-process, which was tested on Fedora and Alpine images. `genericcloud` 12 tested straight from the qcow2 here: `--provision cloud-init`, then `exec` as root. `generic` 13 tested the same way. `generic` has a full kernel and `genericcloud` a smaller one for virtual machines. 11 tested the same way (both cloud images show a black screen and no helper in 200 s, and no DHCP lease appears in 75 s, so the guest does not come up: ❌; the 11.11.0 netinst ISO boots to the GRUB installer menu), and so did `generic` 12.
[^debian-testing]: Testing is the next stable release (forky, 14). Its cloud images are daily builds under `images/cloud/forky/daily/latest/`, and its ISOs are weekly builds; the names are stable. A `trixie/daily/latest` cloud image also exists, for the next 13 point release (not listed). Tested: both forky cloud images (`--provision cloud-init`, then `exec` as root; Debian GNU/Linux forky/sid) and the netinst ISO (GRUB installer menu). The weekly live GNOME ISO boots to its menu, but it is an old build, not testing's: the menu says "Debian GNU/Linux none (trixie)", built 2024-09-02, at 800x600.
[^debian-nocloud]: `nocloud` has no cloud-init (it signs in as root without a password), so `--provision cloud-init` cannot give it the helper; `--provision cloud-init` alone leaves the wizard waiting. `--provision nocloud` answers the first-boot wizard as its questions appear (it reads the screen), logs in as root, and installs the helper from a volume. 13 and forky tested on 2026-11-09, one VM at a time: `exec` as root within 110 s of the start. 13's wizard first asks for a key ("Please configure your system! -- Press any key to proceed --"), then a timezone and root's password; forky's "Initial Setup" starts at the timezone (an earlier forky build showed a login prompt and no wizard, which is why this was ❌). 13 also restarted from a committed overlay with no `--provision` and answered in 11 s, on an earlier run. 12 worked with the earlier recipe, which typed at set times, and was not tried again. 11 does not boot, like its other cloud images (❌). On a Mac with many other VMs running, these guests crashed at boot (a kernel oops from an undefined instruction on 13, a refcount warning in the vsock transport on forky), so test one at a time.
[^debian-installer]: Installers, with no recipe: drive them with `shot`, `click`, `type`, and `key`. The `current` path changes at each point release (13.7.0 today), and 12.15.0 and 11.11.0 sit in the archive. The archive has no arm64 DVD for 11. The DVD-1 ISOs (testing and 12, on 2026-11-09, with 13 earlier) boot to GRUB's installer menu.
[^debian-live]: Debian publishes an arm64 live ISO only as a weekly testing GNOME build. The [`current-live`](https://cdimage.debian.org/debian-cd/current-live/), [`12.15.0-live`](https://cdimage.debian.org/cdimage/archive/12.15.0-live/), and [`11.11.0-live`](https://cdimage.debian.org/cdimage/archive/11.11.0-live/) directories list only `amd64` (and `i386` and `source`), so the live ISOs for GNOME, KDE, Xfce, Cinnamon, MATE, LXDE, and LXQt are amd64 only.

### Pop!_OS

System76 publishes arm64 live ISOs for 24.04 LTS only[^pop].

```
terrarium run IMAGE
```

| Variant | 🟩 24.04 LTS |
|---|---|
| ARM generic ISO | ✅ [2.89 GB](https://iso.pop-os.org/24.04/arm64/generic/3/pop-os_24.04_arm64_generic_3.iso) |
| ARM NVIDIA ISO | ✅ [3.21 GB](https://iso.pop-os.org/24.04/arm64/nvidia/3/pop-os_24.04_arm64_nvidia_3.iso) |

[^pop]: Source: [System76's download page](https://system76.com/pop/download) and its build API, `https://api.pop-os.org/builds/24.04/generic?arch=arm64` (a `GET`; it answers with the ISO's URL, size, and SHA-256). System76 builds these for ARM hardware (the Thelio Astra, and devices that Tow-Boot supports). The generic ISO is a UEFI live image and may boot in a VM; untested. The NVIDIA ISO targets NVIDIA GPUs, which a VM lacks. There is no 22.04 arm64 build.

### Zorin OS

🚫 No aarch64 build. [The download page](https://zorin.com/os/download/) offers Zorin OS 18.1 (Core, Pro, and Education) with no Arm option, and [its requirements](https://help.zorin.com/docs/getting-started/system-requirements/) ask for an Intel or AMD 64-bit processor.

### Fedora

Releases 45, 44, and 43, and Rawhide, the nightly. Fedora has no LTS; each release is supported for about a year. Paths are on `download.fedoraproject.org`, which redirects to a mirror.

```
terrarium run CLOUD_IMAGE --provision cloud-init
terrarium run ISO_IMAGE
```

| Variant | 🟧 Rawhide[^fedora-rawhide] | 🟩 45 | 🟩 44 | 🟫 43 |
|---|---|---|---|---|
| Workstation Live ISO[^fedora-live] | ✅ [2.98 GB](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Workstation/aarch64/iso/Fedora-Workstation-Live-Rawhide-20261109.n.0.aarch64.iso) | ✅ [2.99 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Workstation/aarch64/iso/Fedora-Workstation-Live-45-1.4.aarch64.iso) | ✅ [2.69 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Workstation/aarch64/iso/Fedora-Workstation-Live-44-1.7.aarch64.iso) | ✅ [2.57 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/43/Workstation/aarch64/iso/Fedora-Workstation-Live-43-1.6.aarch64.iso) |
| Workstation Disk (raw.xz) | ✅ [3.18 GB](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Workstation/aarch64/images/Fedora-Workstation-Disk-Rawhide-20261109.n.0.aarch64.raw.xz) | ✅ [3.22 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Workstation/aarch64/images/Fedora-Workstation-Disk-45-1.4.aarch64.raw.xz) | ✅ [2.93 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Workstation/aarch64/images/Fedora-Workstation-Disk-44-1.7.aarch64.raw.xz) | ✅ [3.00 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/43/Workstation/aarch64/images/Fedora-Workstation-Disk-43-1.6.aarch64.raw.xz) |
| Cloud Base (qcow2)[^fedora-cloud] | ✅ [0.62 GB](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Cloud/aarch64/images/Fedora-Cloud-Base-Generic-Rawhide-20261109.n.0.aarch64.qcow2) | ✅ [0.60 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Cloud/aarch64/images/Fedora-Cloud-Base-Generic-45-1.4.aarch64.qcow2) | ✅ [0.53 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/aarch64/images/Fedora-Cloud-Base-Generic-44-1.7.aarch64.qcow2) | ✅ [0.54 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/43/Cloud/aarch64/images/Fedora-Cloud-Base-Generic-43-1.6.aarch64.qcow2) |
| Cloud UEFI-UKI (qcow2) | ✅ [0.64 GB](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Cloud/aarch64/images/Fedora-Cloud-Base-UEFI-UKI-Rawhide-20261109.n.0.aarch64.qcow2) | ✅ [0.62 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Cloud/aarch64/images/Fedora-Cloud-Base-UEFI-UKI-45-1.4.aarch64.qcow2) | ✅ [0.56 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/aarch64/images/Fedora-Cloud-Base-UEFI-UKI-44-1.7.aarch64.qcow2) | 🚫 |
| Cloud AmazonEC2 (raw.xz)[^fedora-cloud] | ✅ [0.60 GB](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Cloud/aarch64/images/Fedora-Cloud-Base-AmazonEC2-Rawhide-20261109.n.0.aarch64.raw.xz) | ✅ [0.57 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Cloud/aarch64/images/Fedora-Cloud-Base-AmazonEC2-45-1.4.aarch64.raw.xz) | ✅ [0.51 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/aarch64/images/Fedora-Cloud-Base-AmazonEC2-44-1.7.aarch64.raw.xz) | ✅ [0.51 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/43/Cloud/aarch64/images/Fedora-Cloud-Base-AmazonEC2-43-1.6.aarch64.raw.xz) |
| Minimal (raw.xz)[^fedora-minimal] | ❌ [0.76 GB](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Spins/aarch64/images/Fedora-Minimal-Rawhide-20261109.n.0.aarch64.raw.xz) | ✅ [0.72 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Spins/aarch64/images/Fedora-Minimal-45-1.4.aarch64.raw.xz) | ✅ [0.67 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Spins/aarch64/images/Fedora-Minimal-44-1.7.aarch64.raw.xz) | ✅ [0.72 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/43/Spins/aarch64/images/Fedora-Minimal-43-1.6.aarch64.raw.xz) |
| Server netinst ISO[^fedora-installer] | ✅ [1.62 GB](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Server/aarch64/iso/Fedora-Server-netinst-aarch64-Rawhide-20261109.n.0.iso) | ✅ [1.44 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Server/aarch64/iso/Fedora-Server-netinst-aarch64-45-1.4.iso) | ✅ [1.26 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Server/aarch64/iso/Fedora-Server-netinst-aarch64-44-1.7.iso) | ✅ [1.20 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/43/Server/aarch64/iso/Fedora-Server-netinst-aarch64-43-1.6.iso) |
| Server DVD ISO | ✅ [4.36 GB](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Server/aarch64/iso/Fedora-Server-dvd-aarch64-Rawhide-20261109.n.0.iso) | ✅ [4.15 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Server/aarch64/iso/Fedora-Server-dvd-aarch64-45-1.4.iso) | ✅ [3.66 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Server/aarch64/iso/Fedora-Server-dvd-aarch64-44-1.7.iso) | ✅ [3.36 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/43/Server/aarch64/iso/Fedora-Server-dvd-aarch64-43-1.6.iso) |
| Server Guest (qcow2) | ❌ [1.01 GB](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Server/aarch64/images/Fedora-Server-Guest-Generic-Rawhide-20261109.n.0.aarch64.qcow2) | ❌ [0.98 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Server/aarch64/images/Fedora-Server-Guest-Generic-45-1.4.aarch64.qcow2) | ❌ [0.94 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Server/aarch64/images/Fedora-Server-Guest-Generic-44-1.7.aarch64.qcow2) | ❌ [1.04 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/43/Server/aarch64/images/Fedora-Server-Guest-Generic-43-1.6.aarch64.qcow2) |
| Everything netinst ISO[^fedora-installer] | ✅ [1.61 GB](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Everything/aarch64/iso/Fedora-Everything-netinst-aarch64-Rawhide-20261109.n.0.iso) | ✅ [1.43 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Everything/aarch64/iso/Fedora-Everything-netinst-aarch64-45-1.4.iso) | ✅ [1.25 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Everything/aarch64/iso/Fedora-Everything-netinst-aarch64-44-1.7.iso) | ✅ [1.19 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/43/Everything/aarch64/iso/Fedora-Everything-netinst-aarch64-43-1.6.iso) |
| KDE Plasma Live ISO | ✅ [3.58 GB](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/KDE/aarch64/iso/Fedora-KDE-Desktop-Live-Rawhide-20261109.n.0.aarch64.iso) | ✅ [3.54 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/KDE/aarch64/iso/Fedora-KDE-Desktop-Live-45-1.4.aarch64.iso) | ✅ [3.12 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/KDE/aarch64/iso/Fedora-KDE-Desktop-Live-44-1.7.aarch64.iso) | ✅ [3.09 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/43/KDE/aarch64/iso/Fedora-KDE-Desktop-Live-43-1.6.aarch64.iso) |
| KDE Plasma Disk (raw.xz) | ✅ [4.05 GB](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/KDE/aarch64/images/Fedora-KDE-Desktop-Disk-Rawhide-20261109.n.0.aarch64.raw.xz) | ✅ [4.05 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/KDE/aarch64/images/Fedora-KDE-Desktop-Disk-45-1.4.aarch64.raw.xz) | ✅ [3.65 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/KDE/aarch64/images/Fedora-KDE-Desktop-Disk-44-1.7.aarch64.raw.xz) | ✅ [3.68 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/43/KDE/aarch64/images/Fedora-KDE-Desktop-Disk-43-1.6.aarch64.raw.xz) |
| Xfce Live ISO | ✅ [3.04 GB](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Spins/aarch64/iso/Fedora-Xfce-Live-Rawhide-20261109.n.0.aarch64.iso) | ✅ [2.98 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Spins/aarch64/iso/Fedora-Xfce-Live-45-1.4.aarch64.iso) | ✅ [2.67 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Spins/aarch64/iso/Fedora-Xfce-Live-44-1.7.aarch64.iso) | ✅ [2.66 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/43/Spins/aarch64/iso/Fedora-Xfce-Live-43-1.6.aarch64.iso) |
| LXQt Live ISO | ✅ [2.60 GB](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Spins/aarch64/iso/Fedora-LXQt-Live-Rawhide-20261109.n.0.aarch64.iso) | ✅ [2.55 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Spins/aarch64/iso/Fedora-LXQt-Live-45-1.4.aarch64.iso) | ✅ [2.21 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Spins/aarch64/iso/Fedora-LXQt-Live-44-1.7.aarch64.iso) | ✅ [2.17 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/43/Spins/aarch64/iso/Fedora-LXQt-Live-43-1.6.aarch64.iso) |
| i3 Live ISO | ✅ [2.55 GB](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Spins/aarch64/iso/Fedora-i3-Live-Rawhide-20261109.n.0.aarch64.iso) | ✅ [2.50 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Spins/aarch64/iso/Fedora-i3-Live-45-1.4.aarch64.iso) | ✅ [2.21 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Spins/aarch64/iso/Fedora-i3-Live-44-1.7.aarch64.iso) | ✅ [2.21 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/43/Spins/aarch64/iso/Fedora-i3-Live-43-1.6.aarch64.iso) |
| COSMIC Live ISO | ✅ [3.29 GB](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Spins/aarch64/iso/Fedora-COSMIC-Live-Rawhide-20261109.n.0.aarch64.iso) | ✅ [3.23 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Spins/aarch64/iso/Fedora-COSMIC-Live-45-1.4.aarch64.iso) | ✅ [2.90 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Spins/aarch64/iso/Fedora-COSMIC-Live-44-1.7.aarch64.iso) | ✅ [2.85 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/43/Spins/aarch64/iso/Fedora-COSMIC-Live-43-1.6.aarch64.iso) |
| KDE Mobile Live ISO | ✅ [2.79 GB](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Spins/aarch64/iso/Fedora-KDE-Mobile-Live-Rawhide-20261109.n.0.aarch64.iso) | ✅ [2.73 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Spins/aarch64/iso/Fedora-KDE-Mobile-Live-45-1.4.aarch64.iso) | ✅ [2.43 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Spins/aarch64/iso/Fedora-KDE-Mobile-Live-44-1.7.aarch64.iso) | ✅ [2.50 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/43/Spins/aarch64/iso/Fedora-KDE-Mobile-Live-43-1.6.aarch64.iso) |
| MiracleWM Live ISO | — | ✅ [2.60 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Spins/aarch64/iso/Fedora-MiracleWM-Live-45-1.4.aarch64.iso) | ✅ [2.28 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Spins/aarch64/iso/Fedora-MiracleWM-Live-44-1.7.aarch64.iso) | ✅ [2.25 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/43/Spins/aarch64/iso/Fedora-MiracleWM-Live-43-1.6.aarch64.iso) |
| SoaS Live ISO | ✅ [2.40 GB](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Spins/aarch64/iso/Fedora-SoaS-Live-Rawhide-20261109.n.0.aarch64.iso) | ✅ [2.35 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Spins/aarch64/iso/Fedora-SoaS-Live-45-1.4.aarch64.iso) | ✅ [2.06 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Spins/aarch64/iso/Fedora-SoaS-Live-44-1.7.aarch64.iso) | ✅ [2.07 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/43/Spins/aarch64/iso/Fedora-SoaS-Live-43-1.6.aarch64.iso) |
| Silverblue installer ISO[^fedora-atomic] | ✅ [3.42 GB](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Silverblue/aarch64/iso/Fedora-Silverblue-Installer-Rawhide-20261109.n.0.aarch64.iso) | ✅ [3.08 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Silverblue/aarch64/iso/Fedora-Silverblue-Installer-45-1.4.aarch64.iso) | ✅ [3.16 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Silverblue/aarch64/iso/Fedora-Silverblue-ostree-aarch64-44-1.7.iso) | ✅ [3.02 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/43/Silverblue/aarch64/iso/Fedora-Silverblue-ostree-aarch64-43-1.6.iso) |
| Kinoite installer ISO[^fedora-atomic] | ✅ [4.17 GB](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Kinoite/aarch64/iso/Fedora-Kinoite-Installer-Rawhide-20261109.n.0.aarch64.iso) | ✅ [3.76 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Kinoite/aarch64/iso/Fedora-Kinoite-Installer-45-1.4.aarch64.iso) | ✅ [3.88 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Kinoite/aarch64/iso/Fedora-Kinoite-ostree-aarch64-44-1.7.iso) | ✅ [3.73 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/43/Kinoite/aarch64/iso/Fedora-Kinoite-ostree-aarch64-43-1.6.iso) |
| COSMIC Atomic installer ISO[^fedora-atomic] | ✅ [3.16 GB](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/COSMIC-Atomic/aarch64/iso/Fedora-CosmicAtomic-Installer-Rawhide-20261109.n.0.aarch64.iso) | ✅ [3.11 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/COSMIC-Atomic/aarch64/iso/Fedora-CosmicAtomic-Installer-45-1.4.aarch64.iso) | ✅ [2.59 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/COSMIC-Atomic/aarch64/iso/Fedora-COSMIC-Atomic-ostree-aarch64-44-1.7.iso) | ✅ [2.53 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/43/COSMIC-Atomic/aarch64/iso/Fedora-COSMIC-Atomic-ostree-aarch64-43-1.6.iso) |
| Python Classroom Live ISO | — | ✅ [3.16 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Labs/aarch64/iso/Fedora-Python-Classroom-Live-45-1.4.aarch64.iso) | ✅ [2.83 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Labs/aarch64/iso/Fedora-Python-Classroom-Live-44-1.7.aarch64.iso) | ✅ [2.72 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/43/Labs/aarch64/iso/Fedora-Python-Classroom-Live-43-1.6.aarch64.iso) |
| Scientific KDE Live ISO | — | ✅ [6.46 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Labs/aarch64/iso/Fedora-Scientific_KDE-Live-45-1.4.aarch64.iso) | ✅ [5.68 GB](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Labs/aarch64/iso/Fedora-Scientific_KDE-Live-44-1.7.aarch64.iso) | 🚫 |
| IoT (raw.xz)[^fedora-iot] | — | ❌ [0.95 GB](https://dl.fedoraproject.org/pub/alt/iot/45/IoT/aarch64/images/Fedora-IoT-raw-45-20261031.0.aarch64.raw.xz) | ❌ [0.89 GB](https://dl.fedoraproject.org/pub/alt/iot/44/IoT/aarch64/images/Fedora-IoT-raw-44-20260427.0.aarch64.raw.xz) | ❌ [0.90 GB](https://dl.fedoraproject.org/pub/alt/iot/43/IoT/aarch64/images/Fedora-IoT-raw-43-20251024.0.aarch64.raw.xz) |

CoreOS (stable stream, `applehv` build for Apple's Virtualization framework): ❌ [1.01 GB](https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/44.20261023.3.1/aarch64/fedora-coreos-44.20261023.3.1-applehv.aarch64.raw.gz) [^fedora-coreos]

Not built for aarch64 in any of these releases: 🚫 the MATE, Cinnamon, Budgie, LXDE, and Sway live spins and Budgie Atomic. Sericea and Sway Atomic publish OCI archives, which are not bootable disks.

Each live spin also has a pre-installed `-Disk-` `.raw.xz` next to its ISO under `images/`; only the Workstation and KDE Plasma ones are listed. Tested on 2026-11-09, with no recipe (no helper): the Workstation Disks reach GNOME's *Setup* welcome page (Rawhide, 45, 44, and 43) and the KDE Plasma Disks Plasma's *Begin Setup* page (Rawhide, 45, 44) or, for 43, the text *Initial Setup* menu.

[^fedora-rawhide]: Rawhide is Fedora's nightly. Its file names carry the compose date (`Rawhide-20261109.n.0` here) and there is no `latest` alias, so these links work for about a day. To pull a later one, read [`development/rawhide/COMPOSE_ID`](https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/COMPOSE_ID) and put its date in the name (`Fedora-Rawhide-YYYYMMDD.n.0` becomes `Rawhide-YYYYMMDD.n.0`). Rawhide has no MiracleWM or IoT images, and its Labs images were not checked. Tested on 2026-11-08 (Fedora 46 prerelease): the Cloud Base, UKI, and AmazonEC2 images with `--provision cloud-init`, then `exec` as root; the Workstation, KDE Plasma, Xfce, LXQt, i3, COSMIC, KDE Mobile, and SoaS live ISOs and the Server and Everything netinst ISOs and the Silverblue, Kinoite, and COSMIC Atomic installers each reached their session or first screen after 200 s. The Minimal and Server Guest disks gave no helper in 200 s (❌, as for 45). The disks, Disk images, and DVD were not tested.
[^fedora-live]: 44 tested: a GNOME session driven with `click`, `scroll`, `drag`, `type`, and `key`, and the Linux Send Key chords. The welcome screen appears after about 100 s with 4 GiB and 4 CPUs. The image has no helper and no recipe, so there is no `exec`. 45 tested too (a `shot` after two minutes): the Workstation, KDE Plasma, Xfce, LXQt, i3, COSMIC, KDE Mobile, SoaS, Python Classroom, and MiracleWM live ISOs each reached their session or first-run screen (i3 asks whether to generate its config, SoaS asks for a name, MiracleWM shows its DMS welcome), and the Silverblue, Kinoite, and COSMIC Atomic installers reached Anaconda's welcome page (after more than 140 s). Nothing was driven further. The 44 and 43 spins and installers tested the same way (the Kinoite, Silverblue, and COSMIC Atomic `ostree` ISOs reach Anaconda's welcome page too); so did the 43 Workstation ISO.
[^fedora-cloud]: Cloud Base 45 tested: `--provision cloud-init`, then `exec` as root, checked again on 2026-11-08 after the OpenRC change to that recipe. 44 was tested earlier with its AmazonEC2 `raw.xz` (`--provision cloud-init`, `exec`, `commit`, and a restart from the overlay). The 45 UKI qcow2 and AmazonEC2 `raw.xz` tested the same way (`exec` as root). The 44 and 43 qcow2 files are untested.
[^fedora-minimal]: 44 tested only as far as booting, taking a DHCP lease, answering ping, and working console and input. The image has no recipe, so put the helper in by hand to use `exec`. 45 and 43 tested the same way on 2026-11-09: they boot to the *Initial Setup* menu on the console (language, time, root password, and user creation unset), which waits for answers, so the helper is not started. The Scientific KDE live ISOs (45 and 44) boot to Plasma's Welcome Center, and the Server DVD ISOs (Rawhide, 45, 44, and 43) to Anaconda's welcome page.
[^fedora-installer]: Installers, with no recipe: Server netinst and DVD, and Everything netinst. Drive them with `shot`, `click`, `type`, and `key`. The 45 Server and Everything netinst ISOs boot to Anaconda's welcome screen. The Server Guest qcow2 is a prebuilt guest: 45 tested with `--provision cloud-init`, and `exec` never answered in 200 s; its console sat at the initial-setup prompt ("Please make a selection from the above ['c' to continue…]"), so the guest waits for an answer before the helper starts. The same wizard is on the display (root password and user creation unset), so `type` and `key` can answer it. 44 and 43 stop at it too, and so does Fedora Minimal 43.
[^fedora-atomic]: Installer ISOs, with no recipe. The 45 files are named `Installer`; the 44 and 43 ones `ostree`. 45 also publishes ready-made `Disk` and `QCOW` images for Silverblue and Kinoite, not listed here.
[^fedora-iot]: The IoT URLs carry the build date and change when a new build is published. 44 and 43 the same, and 45 tested: `--provision cloud-init` started, and `exec` never answered in 200 s. It boots to a login prompt ("Ignition: no config provided by user") with no account to log in to. The others are untested.
[^fedora-coreos]: CoreOS provisions with Ignition, not cloud-init, so neither `--provision cloud-init` nor `--provision alpine` applies. The URL carries the build ID (44.20261023.3.1) and changes with each stable build. Tested: `--provision cloud-init` started, and `exec` never answered in 200 s. It does not boot: its Ignition tries to fetch the config from the host over vsock port 1024 (Podman's applehv arrangement), gets "connection reset by peer", and drops to emergency mode, so serving a config on that port would be a feature.

### EndeavourOS

🚫 No generic aarch64 image. [The ISO mirror](https://mirror.alpix.eu/endeavouros/iso/) lists no Arm ISO, and [the Arm project](https://github.com/endeavouros-arm/images/releases) publishes images for the Raspberry Pi 4 and 5, ODROID-N2, and Pinebook Pro only.

### Ubuntu

Long-term support (LTS) releases 22.04, 24.04, and 26.04, and the current release, 26.10.

```
terrarium run CLOUD_IMAGE --provision cloud-init
terrarium run DESKTOP_ISO --provision cloud-init --tweak ubuntu-no-welcome
terrarium run INSTALLER_ISO
```

| Variant | 🟧 daily[^ubuntu-daily] | 🟧 26.10 | 🟩 26.04 LTS | 🟩 24.04 LTS | 🟫 22.04 LTS |
|---|---|---|---|---|---|
| Desktop ISO[^ubuntu-desktop] | — | ✅ [4.60 GB](https://cdimage.ubuntu.com/releases/26.10/release/ubuntu-26.10-desktop-arm64.iso) | ✅ [4.15 GB](https://cdimage.ubuntu.com/releases/26.04.1/release/ubuntu-26.04.1-desktop-arm64.iso) | ✅ [3.97 GB](https://cdimage.ubuntu.com/releases/24.04.5/release/ubuntu-24.04.5-desktop-arm64.iso) | 🚫 |
| Live server ISO[^ubuntu-installer] | — | ✅ [3.08 GB](https://cdimage.ubuntu.com/releases/26.10/release/ubuntu-26.10-live-server-arm64.iso) | ✅ [3.08 GB](https://cdimage.ubuntu.com/releases/26.04.1/release/ubuntu-26.04.1-live-server-arm64.iso) | ✅ [3.83 GB](https://cdimage.ubuntu.com/releases/24.04.5/release/ubuntu-24.04.5-live-server-arm64.iso) | ✅ [2.06 GB](https://cdimage.ubuntu.com/releases/22.04.5/release/ubuntu-22.04.5-live-server-arm64.iso) |
| Preinstalled server (img.xz)[^ubuntu-installer] | — | ✅ [1.48 GB](https://cdimage.ubuntu.com/releases/26.10/release/ubuntu-26.10-preinstalled-server-arm64.img.xz) | ✅ [1.36 GB](https://cdimage.ubuntu.com/releases/26.04.1/release/ubuntu-26.04.1-preinstalled-server-arm64.img.xz) | ✅ [1.20 GB](https://cdimage.ubuntu.com/releases/24.04.5/release/ubuntu-24.04.5-preinstalled-server-arm64.img.xz) | 🚫 |
| Cloud image[^ubuntu-cloud] | — | ✅ [0.98 GB](https://cloud-images.ubuntu.com/releases/stonking/release/ubuntu-26.10-server-cloudimg-arm64.img) | ✅ [0.94 GB](https://cloud-images.ubuntu.com/releases/resolute/release/ubuntu-26.04-server-cloudimg-arm64.img) | ✅ [0.62 GB](https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-arm64.img) | ✅ [0.70 GB](https://cloud-images.ubuntu.com/releases/jammy/release/ubuntu-22.04-server-cloudimg-arm64.img) |
| Minimal cloud image[^ubuntu-cloud] | — | ✅ [0.41 GB](https://cloud-images.ubuntu.com/minimal/releases/stonking/release/ubuntu-26.10-minimal-cloudimg-arm64.img) | ✅ [0.40 GB](https://cloud-images.ubuntu.com/minimal/releases/resolute/release/ubuntu-26.04-minimal-cloudimg-arm64.img) | ✅ [0.22 GB](https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-arm64.img) | 🚫 |

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

```
terrarium run CLOUD_IMAGE --provision cloud-init
terrarium run KVM_IMAGE --provision combustion
terrarium run ISO_IMAGE
```

| Variant | 🟧 Tumbleweed | 🟩 Leap 16.1 | 🟫 Leap 16.0 | 🟫 Leap 15.6 |
|---|---|---|---|---|
| Offline installer ISO (DVD on 15.6)[^suse-installer] | ✅ [4.24 GB](https://download.opensuse.org/ports/aarch64/tumbleweed/iso/openSUSE-Tumbleweed-DVD-aarch64-Current.iso) | ✅ [4.61 GB](https://download.opensuse.org/distribution/leap/16.1/offline/Leap-16.1-offline-installer-aarch64.install.iso) | ✅ [4.64 GB](https://download.opensuse.org/distribution/leap/16.0/offline/Leap-16.0-offline-installer-aarch64.install.iso) | ✅ [4.67 GB](https://download.opensuse.org/distribution/leap/15.6/iso/openSUSE-Leap-15.6-DVD-aarch64-Current.iso) |
| Online installer ISO (NET on 15.6) | ✅ [0.46 GB](https://download.opensuse.org/ports/aarch64/tumbleweed/iso/openSUSE-Tumbleweed-NET-aarch64-Current.iso) | ✅ [0.77 GB](https://download.opensuse.org/distribution/leap/16.1/offline/Leap-16.1-online-installer-aarch64.install.iso) | ✅ [0.75 GB](https://download.opensuse.org/distribution/leap/16.0/offline/Leap-16.0-online-installer-aarch64.install.iso) | ✅ [0.30 GB](https://download.opensuse.org/distribution/leap/15.6/iso/openSUSE-Leap-15.6-NET-aarch64-Current.iso) |
| GNOME Live ISO | ✅ [1.44 GB](https://download.opensuse.org/ports/aarch64/tumbleweed/iso/openSUSE-Tumbleweed-GNOME-Live-aarch64-Current.iso) | 🚫 | 🚫 | — |
| KDE Live ISO | ✅ [1.44 GB](https://download.opensuse.org/ports/aarch64/tumbleweed/iso/openSUSE-Tumbleweed-KDE-Live-aarch64-Current.iso) | 🚫 | 🚫 | — |
| XFCE Live ISO | ✅ [1.40 GB](https://download.opensuse.org/ports/aarch64/tumbleweed/iso/openSUSE-Tumbleweed-XFCE-Live-aarch64-Current.iso) | 🚫 | 🚫 | — |
| Minimal-VM kvm (qcow2)[^suse-kvm] | ✅ [0.27 GB](https://download.opensuse.org/ports/aarch64/tumbleweed/appliances/openSUSE-Tumbleweed-Minimal-VM.aarch64-kvm-and-xen.qcow2) | ✅ [0.31 GB](https://download.opensuse.org/distribution/leap/16.1/appliances/Leap-16.1-Minimal-VM.aarch64-kvm.qcow2) | ✅ [0.30 GB](https://download.opensuse.org/distribution/leap/16.0/appliances/Leap-16.0-Minimal-VM.aarch64-kvm.qcow2) | ❌ [0.26 GB](https://download.opensuse.org/distribution/leap/15.6/appliances/openSUSE-Leap-15.6-Minimal-VM.aarch64-kvm.qcow2) |
| Minimal-VM Cloud (qcow2)[^suse-cloud] | ✅ [0.29 GB](https://download.opensuse.org/ports/aarch64/tumbleweed/appliances/openSUSE-Tumbleweed-Minimal-VM.aarch64-Cloud.qcow2) | ✅ [0.32 GB](https://download.opensuse.org/distribution/leap/16.1/appliances/Leap-16.1-Minimal-VM.aarch64-Cloud.qcow2) | ✅ [0.32 GB](https://download.opensuse.org/distribution/leap/16.0/appliances/Leap-16.0-Minimal-VM.aarch64-Cloud.qcow2) | ✅ [0.27 GB](https://download.opensuse.org/distribution/leap/15.6/appliances/openSUSE-Leap-15.6-Minimal-VM.aarch64-Cloud.qcow2) |
| JeOS efi (qcow2) | ✅ [1.29 GB](https://download.opensuse.org/ports/aarch64/tumbleweed/appliances/openSUSE-Tumbleweed-ARM-JeOS-efi.aarch64.qcow2) | — | — | ❌ [0.97 GB](https://download.opensuse.org/distribution/leap/15.6/appliances/openSUSE-Leap-15.6-ARM-JeOS-efi.aarch64.qcow2) |
| KDE efi (raw.xz) | ✅ [1.92 GB](https://download.opensuse.org/ports/aarch64/tumbleweed/appliances/openSUSE-Tumbleweed-ARM-KDE-efi.aarch64.raw.xz) | — | — | ✅ [1.63 GB](https://download.opensuse.org/distribution/leap/15.6/appliances/openSUSE-Leap-15.6-ARM-KDE-efi.aarch64.raw.xz) |
| GNOME efi (raw.xz) | ✅ [1.78 GB](https://download.opensuse.org/ports/aarch64/tumbleweed/appliances/openSUSE-Tumbleweed-ARM-GNOME-efi.aarch64.raw.xz) | — | — | ✅ [1.54 GB](https://download.opensuse.org/distribution/leap/15.6/appliances/openSUSE-Leap-15.6-ARM-GNOME-efi.aarch64.raw.xz) |
| XFCE efi (raw.xz) | ✅ [1.87 GB](https://download.opensuse.org/ports/aarch64/tumbleweed/appliances/openSUSE-Tumbleweed-ARM-XFCE-efi.aarch64.raw.xz) | — | — | ✅ [1.60 GB](https://download.opensuse.org/distribution/leap/15.6/appliances/openSUSE-Leap-15.6-ARM-XFCE-efi.aarch64.raw.xz) |

Leap 16 has the Agama installers only; its live desktops exist for Tumbleweed. The `64kb`, real-time, and encrypted image variants also exist, and are not listed. The `efi` ARM images target generic UEFI. Tumbleweed's JeOS takes `--provision cloud-init` (`exec` as root). Leap 15.6's JeOS crashes about 35 s into its boot (a kernel oops from an undefined instruction in `btrfs_compress_heuristic`), after which `exec` waits forever on the dead guest (❌). The KDE, GNOME, and XFCE ones boot to a login screen with no helper (✅ as a boot).

[^suse-installer]: Installers, with no recipe: drive them with `shot`, `click`, `type`, and `key`. The Leap 16 online installer sits in the `offline/` directory. The Leap 16.0 installers reach Agama's product page (Leap 16.0 and Leap Micro 6.2, the offline one), and Leap 15.6's NET ISO reaches YaST's license page. Leap 16.1's online and offline installers boot to Agama's *Select a mode* page.
[^suse-kvm]: The Minimal-VM `kvm` images boot UEFI and configure themselves at first boot with Combustion or Ignition, not cloud-init (`--provision cloud-init` gave no helper in 200 s). `--provision combustion` tested on 2026-11-09: Tumbleweed, Leap 16.1, and Leap 16.0 answer `exec` as root (openSUSE Tumbleweed; Leap 16.1; Leap 16.0), though each still shows its JeOS Firstboot dialog on the display. Leap 15.6's image does not: it waits at the JeOS Firstboot dialog (*Welcome to openSUSE Leap 15.6!*, with a Start button) and no helper starts, so Combustion did not run (❌).
[^suse-cloud]: Leap 16.1's `Cloud` image tested: `--provision cloud-init`, then `exec` as root. The `Cloud` and `OpenStack-Cloud` images are the cloud-init ones (that part is from memory of openSUSE's image definitions), so the others are expected to work the same; untested.

Atomic (transactional) editions:

```
terrarium run CLOUD_IMAGE --provision cloud-init
terrarium run KVM_IMAGE --provision combustion
```

| Variant | 🟧 MicroOS | 🟩 Leap Micro 6.2 |
|---|---|---|
| Installer ISO | ✅ [3.07 GB](https://download.opensuse.org/ports/aarch64/tumbleweed/iso/openSUSE-MicroOS-DVD-aarch64-Current.iso) | ❌ [1.59 GB](https://download.opensuse.org/distribution/leap-micro/6.2/product/iso/openSUSE-Leap-Micro-6.2-aarch64.iso) |
| Disk image (qcow2)[^suse-atomic] | ✅ [0.54 GB](https://download.opensuse.org/ports/aarch64/tumbleweed/appliances/openSUSE-MicroOS.aarch64-kvm-and-xen.qcow2) | ✅ [1.48 GB](https://download.opensuse.org/distribution/leap-micro/6.2/appliances/openSUSE-Leap-Micro.aarch64-Default-qcow.qcow2) |
| Cloud image (qcow2)[^suse-cloud] | ✅ [0.53 GB](https://download.opensuse.org/ports/aarch64/tumbleweed/appliances/openSUSE-MicroOS.aarch64-OpenStack-Cloud.qcow2) | — |

[^suse-atomic]: Leap Micro and MicroOS configure at first boot with Ignition or combustion. `--provision combustion` tested on 2026-11-09: the MicroOS kvm-and-xen qcow2 and the Leap Micro 6.2 qcow2 answer `exec` as root (openSUSE MicroOS; openSUSE Leap Micro 6.2). The recipe puts the helper in `/usr/bin`: `/usr/local` is not in the snapshot that Combustion updates (and does not exist on Leap Micro, where the first attempt failed). MicroOS's OpenStack Cloud qcow2 and the Leap Micro 6.2 qcow2 also tested with `--provision cloud-init`, then `exec` as root. The Leap Micro 6.2 ISO tested: `start` returned, and the VM stopped by itself within a second or two, with empty serve and console logs (cause not found: the ISO has no El Torito boot record, no MBR, and no GPT, so nothing in it can boot as a disk; `start` now fails with "the guest stopped itself", as it does for the Oracle 8 ISO). The others are untested.

🚫 Slowroll has x86_64 images only ([its ISO listing](https://download.opensuse.org/slowroll/iso/)), and Aeon and Kalpa have no aarch64 files in [the Tumbleweed ports listing](https://download.opensuse.org/ports/aarch64/tumbleweed/iso/).

### Nobara

🚫 No aarch64 build. [The download page](https://nobaraproject.org/download-nobara/) lists only the `Nobara-44-*.iso` files, which are x86_64.

### NixOS

```
terrarium run IMAGE
```

| Variant | 🟧 unstable | 🟩 26.05 |
|---|---|---|
| Minimal ISO | ✅ [1.83 GB](https://channels.nixos.org/nixos-unstable/latest-nixos-minimal-aarch64-linux.iso) | ✅ [1.82 GB](https://channels.nixos.org/nixos-26.05/latest-nixos-minimal-aarch64-linux.iso) |
| Graphical ISO | ✅ [4.00 GB](https://channels.nixos.org/nixos-unstable/latest-nixos-graphical-aarch64-linux.iso) | ✅ [3.93 GB](https://channels.nixos.org/nixos-26.05/latest-nixos-graphical-aarch64-linux.iso) |

### elementary OS

elementary OS 8.1.1 (Circe) publishes an arm64 ISO with no stable URL: the "Pay What You Can" download on [elementary.io](https://elementary.io/) goes through a payment page, but the page's own source carries a direct link whose path is a token, and a link that was fresh when the page was served is not one to keep[^elementary]. The result below is of a link that has since expired, and it still holds for the file.

```
terrarium run IMAGE
```

| Variant | 🟩 8.1.1 Circe |
|---|---|
| Desktop ISO[^elementary] | ✅ [3.19 GB](https://elementary.io/) |

[^elementary]: Tested 2026-11-09 on `elementaryos-8.1-stable-arm64.20260219.iso`, whose direct link was `https://dl.elementaryos.org/MTc5NDI1MjQyNg==/elementaryos-8.1-stable-arm64.20260219.iso`. The token is base64 of a Unix timestamp (`1794252426`, the moment the page was fetched), the link answered 200 and redirected to a signed storage URL, and how long it lasts was not measured; fetch the page again for a fresh one. The page also offers a magnet link for the same file (`urn:btih:90b3382caff769f4c7779ef90a5ab30eedda73d4`), which does not expire: fetch it with a torrent client and `pull` the file. `pull` of the ISO took 52 s; it needs no conversion. Booted with 4 GiB and 4 CPUs and no recipe (no helper, so no `exec`): after two minutes the display (1280x800) showed the live session's *Select a Language* window on the desktop wallpaper, and a `click` on *Select* moved it on to the list of English regions (so pointer input works); nothing was driven past that, and the installer was not run.

### Void Linux

```
terrarium run IMAGE
```

| Variant | 🟩 20250202 |
|---|---|
| Live base ISO (glibc)[^void] | ✅ [1.17 GB](https://repo-default.voidlinux.org/live/current/void-live-aarch64-20250202-base.iso) |
| Live Xfce ISO (glibc)[^void] | ✅ [1.50 GB](https://repo-default.voidlinux.org/live/current/void-live-aarch64-20250202-xfce.iso) |

[^void]: Void's newest aarch64 live build is older than its x86_64 ones. Both ISOs tested: the base one boots to a text login (`root` and `anon`, password `voidlinux`), and the Xfce one to a logged-in Xfce desktop. The Asahi ISO is for Apple silicon hardware, not a VM.

### Alpine

3.24 and 3.23, from `dl-cdn.alpinelinux.org`. The [cloud images](https://alpinelinux.org/cloud/) come in `cloudinit` and `tiny` variants.

```
terrarium run CLOUD_IMAGE --provision cloud-init
terrarium run ISO_IMAGE --provision alpine --tweak no-blank --tweak alpine-repositories
terrarium run ISO_IMAGE --install alpine
```

| Variant | 🟧 edge[^alpine-edge] | 🟩 3.24.4 | 🟫 3.23.8 |
|---|---|---|---|
| Standard ISO[^alpine-live] | — | ✅ [0.39 GB](https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/aarch64/alpine-standard-3.24.4-aarch64.iso) | ✅ [0.39 GB](https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/aarch64/alpine-standard-3.23.8-aarch64.iso) |
| Virt ISO[^alpine-live] | — | ✅ [0.09 GB](https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/aarch64/alpine-virt-3.24.4-aarch64.iso) | ✅ [0.09 GB](https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/aarch64/alpine-virt-3.23.8-aarch64.iso) |
| Cloud, cloud-init (qcow2)[^alpine-cloud] | — | ✅ [0.19 GB](https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/cloud/alpine-3.24.4-aarch64-cloudinit-r0.qcow2) | ✅ [0.22 GB](https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/cloud/alpine-3.23.8-aarch64-uefi-cloudinit-r0.qcow2) |
| Cloud, Tiny Cloud (qcow2)[^alpine-tiny] | — | ❌ [0.13 GB](https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/cloud/alpine-3.24.4-aarch64-tiny-r0.qcow2) | ❌ [0.15 GB](https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/cloud/alpine-3.23.8-aarch64-uefi-tiny-r0.qcow2) |

[^alpine-edge]: Alpine's [`edge` aarch64 directory](https://dl-cdn.alpinelinux.org/alpine/edge/releases/aarch64/) holds no ISOs or cloud images, only netboot and minirootfs tarballs last built 2026-08-05, so there is nothing to pull as a VM.
[^alpine-live]: Standard 3.24.4 tested: `--provision alpine` gives the live session the helper, so `exec` works (sign in as `root`, no password). `--install alpine` to a disk, the `linux/no-blank` and `linux/alpine-repositories` tweaks, and `commit` were tested on 3.24.3. The virt ISO 3.24.4 and the 3.23.8 standard and virt ISOs tested only as far as booting to the console login prompt; they have no helper. The 3.23 cloud image tested like 3.24: `--provision cloud-init` (OpenRC), then `exec` as root.
[^alpine-cloud]: The `cloudinit` variant of 3.24.4 tested: `--provision cloud-init` (the OpenRC path), `exec` as root, `commit`, and a restart from the overlay without `--provision` in about 20 s. The image's own login user is `alpine`. The 3.23 files carry `uefi` in their names and are untested.
[^alpine-tiny]: `tiny` images bootstrap with Tiny Cloud, which `--provision cloud-init` does not drive; put the helper in by hand. 3.24.4 and 3.23.8 tested: `--provision cloud-init` started, and `exec` never answered in 200 s. It boots fully to a login prompt (Tiny Cloud reports `Unknown Cloud 'unknown'` and finds no user data), so only the helper is missing.

### Kali Linux

```
terrarium run CLOUD_IMAGE --provision cloud-init
terrarium run ISO_IMAGE
```

| Variant | 🟧 2026-W46 (weekly)[^kali-weekly] | 🟩 2026.3 |
|---|---|---|
| Installer ISO (offline) | ✅ [3.88 GB](https://cdimage.kali.org/kali-weekly/kali-linux-2026-W46-installer-arm64.iso) | ✅ [4.05 GB](https://cdimage.kali.org/kali-2026.3/kali-linux-2026.3-installer-arm64.iso) |
| Netinst ISO | ✅ [0.61 GB](https://cdimage.kali.org/kali-weekly/kali-linux-2026-W46-installer-netinst-arm64.iso) | ✅ [0.60 GB](https://cdimage.kali.org/kali-2026.3/kali-linux-2026.3-installer-netinst-arm64.iso) |
| Cloud generic (tar.xz)[^kali] | — | ✅ [0.23 GB](https://kali.download/cloud-images/kali-2026.3/kali-linux-2026.3-cloud-genericcloud-arm64.tar.xz) |

[^kali]: The tar holds a disk image and ships cloud-init; `pull` takes a tar of one file, so check that it holds exactly one. Tested: `pull` took the tar, `--provision cloud-init`, then `exec` as root (Kali GNU/Linux Rolling). The live ISO is published only as a torrent. Kali's arm64 VM images for VMware, QEMU, and UTM do not exist, and its ARM images are for boards.
[^kali-weekly]: The names carry the ISO week (`2026-W46`) and the directory holds the latest two, with no `latest` alias, so these links last about a week. Weekly builds are installers only; there are no arm64 live or cloud images in `kali-weekly/`. Both tested: the GRUB installer menu.

### Tails

🚫 No aarch64 build. [Its requirements](https://tails.net/doc/about/requirements/index.en.html) say it needs an x86-64 processor and does not work on ARM.

### Solus

🚫 No aarch64 build. [The download page](https://getsol.us/download/) states a 64-bit x86-64 processor.

### Parrot OS

```
terrarium run IMAGE
```

| Variant | 🟩 7.4 |
|---|---|
| Home ISO | ✅ [3.86 GB](https://deb.parrot.sh/parrot/iso/7.4/Parrot-home-7.4_arm64.iso) |
| Security ISO | ⬜ [8.37 GB](https://deb.parrot.sh/parrot/iso/7.4/Parrot-security-7.4_arm64.iso) |

### AlmaLinux

```
terrarium run CLOUD_IMAGE --provision cloud-init
terrarium run ISO_IMAGE
```

| Variant | 🟧 Kitten 10[^alma-kitten] | 🟩 10.2 | 🟩 9.8 |
|---|---|---|---|
| Boot ISO (netinstall)[^el-installer] | ✅ [1.03 GB](https://repo.almalinux.org/almalinux-kitten/10-kitten/isos/aarch64/AlmaLinux-Kitten-10-latest-aarch64-boot.iso) | ✅ [1.13 GB](https://repo.almalinux.org/almalinux/10/isos/aarch64/AlmaLinux-10.2-aarch64-boot.iso) | ✅ [1.46 GB](https://repo.almalinux.org/almalinux/9/isos/aarch64/AlmaLinux-9.8-aarch64-boot.iso) |
| Minimal ISO[^el-installer] | ✅ [1.56 GB](https://repo.almalinux.org/almalinux-kitten/10-kitten/isos/aarch64/AlmaLinux-Kitten-10-latest-aarch64-minimal.iso) | ✅ [1.66 GB](https://repo.almalinux.org/almalinux/10/isos/aarch64/AlmaLinux-10.2-aarch64-minimal.iso) | ✅ [2.61 GB](https://repo.almalinux.org/almalinux/9/isos/aarch64/AlmaLinux-9.8-aarch64-minimal.iso) |
| DVD ISO[^el-installer] | ✅ [10.10 GB](https://repo.almalinux.org/almalinux-kitten/10-kitten/isos/aarch64/AlmaLinux-Kitten-10-latest-aarch64-dvd.iso) | ✅ [9.59 GB](https://repo.almalinux.org/almalinux/10/isos/aarch64/AlmaLinux-10.2-aarch64-dvd.iso) | ✅ [13.01 GB](https://repo.almalinux.org/almalinux/9/isos/aarch64/AlmaLinux-9.8-aarch64-dvd.iso) |
| Live GNOME ISO[^alma-live] | ✅ [1.70 GB](https://repo.almalinux.org/almalinux-kitten/10-kitten/live/aarch64/AlmaLinux-Kitten-10-latest-aarch64-Live-GNOME.iso) | ✅ [1.82 GB](https://repo.almalinux.org/almalinux/10/live/aarch64/AlmaLinux-10.2-aarch64-Live-GNOME.iso) | ✅ [2.30 GB](https://repo.almalinux.org/almalinux/9/live/aarch64/AlmaLinux-9.8-aarch64-Live-GNOME.iso) |
| Live KDE ISO | ✅ [2.30 GB](https://repo.almalinux.org/almalinux-kitten/10-kitten/live/aarch64/AlmaLinux-Kitten-10-latest-aarch64-Live-KDE.iso) | ✅ [2.51 GB](https://repo.almalinux.org/almalinux/10/live/aarch64/AlmaLinux-10.2-aarch64-Live-KDE.iso) | ✅ [3.13 GB](https://repo.almalinux.org/almalinux/9/live/aarch64/AlmaLinux-9.8-aarch64-Live-KDE.iso) |
| Live MATE ISO | — | 🚫 | ✅ [2.88 GB](https://repo.almalinux.org/almalinux/9/live/aarch64/AlmaLinux-9.8-aarch64-Live-MATE.iso) |
| Live XFCE ISO | — | 🚫 | ✅ [2.47 GB](https://repo.almalinux.org/almalinux/9/live/aarch64/AlmaLinux-9.8-aarch64-Live-XFCE.iso) |
| GenericCloud (qcow2)[^el-cloud] | ✅ [0.48 GB](https://repo.almalinux.org/almalinux-kitten/10-kitten/cloud/aarch64/images/AlmaLinux-Kitten-GenericCloud-10-latest.aarch64.qcow2) | ✅ [0.39 GB](https://repo.almalinux.org/almalinux/10/cloud/aarch64/images/AlmaLinux-10-GenericCloud-latest.aarch64.qcow2) | ✅ [0.45 GB](https://repo.almalinux.org/almalinux/9/cloud/aarch64/images/AlmaLinux-9-GenericCloud-latest.aarch64.qcow2) |
| GenericCloud ext4 (qcow2)[^el-cloud] | ✅ [0.42 GB](https://repo.almalinux.org/almalinux-kitten/10-kitten/cloud/aarch64/images/AlmaLinux-Kitten-GenericCloud-ext4-10-latest.aarch64.qcow2) | ✅ [0.40 GB](https://repo.almalinux.org/almalinux/10/cloud/aarch64/images/AlmaLinux-10-GenericCloud-ext4-latest.aarch64.qcow2) | ✅ [0.44 GB](https://repo.almalinux.org/almalinux/9/cloud/aarch64/images/AlmaLinux-9-GenericCloud-ext4-latest.aarch64.qcow2) |

AlmaLinux 10 publishes only GNOME and KDE live ISOs; MATE, Xfce, and GNOME-Mini exist for 9 only. OpenNebula images also exist, and are not listed.

Enterprise Linux 8 (AlmaLinux 8.10, Rocky 8.10, and Oracle Linux 8) is not listed: none of its images boots under Virtualization. All eleven that were tested failed (the ISOs, the cloud images, and Oracle's `kvm` image); the DVDs, which use the same GRUB, were not tried. On the Rocky 8.10 ISO GRUB itself, before its menu, prints `Invalid call efi_update_mem_attrs ... addr is not page aligned` and hangs (a keypress does nothing); AlmaLinux 8.10 stays black; Oracle 8's ISO makes the VM stop at once, and its cloud images show a black screen.

[^alma-kitten]: AlmaLinux Kitten is the development release, built from CentOS Stream; its `latest` names are stable aliases. Kitten has no MATE or Xfce live ISO. Tested on 2026-11-08: the boot, minimal, Live GNOME, and Live KDE ISOs reach Anaconda's welcome page or the live session, and both GenericCloud images answer `exec` as root after `--provision cloud-init` (AlmaLinux Kitten 10).
[^el-installer]: Installers (Anaconda), with no recipe: drive them with `shot`, `click`, `type`, and `key`. The EL9 and EL10 ISOs boot to Anaconda's welcome page. The DVD ISOs tested the same way on 2026-11-09 (AlmaLinux Kitten, 10.2, and 9.8; CentOS Stream 10 and 9; Rocky 10.3 staging, 10.2, and 9.8): each reaches Anaconda's welcome page. Oracle's two DVD downloads failed, so they are untested.
[^alma-live]: Live ISOs boot to a desktop; there is no recipe and no helper.
[^el-cloud]: GenericCloud images carry cloud-init, and `--provision cloud-init` gives them the helper: tested on Rocky 10.2, 10.3 staging, and 9.8 (also LVM), AlmaLinux 10.2, Kitten, and 9.8 (also ext4 images), and CentOS Stream 10 and 9 (also its ec2 image): `exec` as root, helper active.

### CentOS Stream

```
terrarium run CLOUD_IMAGE --provision cloud-init
terrarium run ISO_IMAGE
```

| Variant | 🟧 10 | 🟩 9 |
|---|---|---|
| Boot ISO[^el-installer] | ✅ [1.03 GB](https://mirror.stream.centos.org/10-stream/BaseOS/aarch64/iso/CentOS-Stream-10-latest-aarch64-boot.iso) | ✅ [1.54 GB](https://mirror.stream.centos.org/9-stream/BaseOS/aarch64/iso/CentOS-Stream-9-latest-aarch64-boot.iso) |
| DVD ISO[^el-installer] | ✅ [10.23 GB](https://mirror.stream.centos.org/10-stream/BaseOS/aarch64/iso/CentOS-Stream-10-latest-aarch64-dvd1.iso) | ✅ [13.82 GB](https://mirror.stream.centos.org/9-stream/BaseOS/aarch64/iso/CentOS-Stream-9-latest-aarch64-dvd1.iso) |
| GenericCloud (qcow2)[^el-cloud] | ✅ [0.89 GB](https://cloud.centos.org/centos/10-stream/aarch64/images/CentOS-Stream-GenericCloud-10-latest.aarch64.qcow2) | ✅ [1.19 GB](https://cloud.centos.org/centos/9-stream/aarch64/images/CentOS-Stream-GenericCloud-9-latest.aarch64.qcow2) |
| ec2 (raw.xz)[^centos-ec2] | ✅ [0.75 GB](https://cloud.centos.org/centos/10-stream/aarch64/images/CentOS-Stream-ec2-10-latest.aarch64.raw.xz) | ✅ [1.12 GB](https://cloud.centos.org/centos/9-stream/aarch64/images/CentOS-Stream-ec2-9-latest.aarch64.raw.xz) |

[^centos-ec2]: A raw disk built for AWS, compressed with xz; same cloud-init arrangement as the qcow2. The 9 image tested: `--provision cloud-init`, then `exec` as root.

### Gentoo

```
terrarium run CLOUD_IMAGE --provision cloud-init
terrarium run ISO_IMAGE
```

| Variant | 🟩 rolling (20261101) |
|---|---|
| Minimal install ISO[^gentoo] | ✅ [0.86 GB](https://distfiles.gentoo.org/releases/arm64/autobuilds/20261101T233055Z/install-arm64-minimal-20261101T233055Z.iso) |
| Disk image, cloud-init (qcow2)[^gentoo] | ✅ [1.42 GB](https://distfiles.gentoo.org/releases/arm64/autobuilds/20261101T233055Z/di-arm64-cloudinit-20261101T233055Z.qcow2) |
| Disk image, console (qcow2)[^gentoo] | ❌ [1.17 GB](https://distfiles.gentoo.org/releases/arm64/autobuilds/20261101T233055Z/di-arm64-console-20261101T233055Z.qcow2) |

[^gentoo]: The URLs carry the build stamp and change with each autobuild. The minimal ISO is Gentoo's generic arm64 install image; it boots under Virtualization to a root console (`livecd`, automatic login) with no helper. The qcow2 images are prebuilt disks; the `cloud-init` one carries cloud-init, and tested: `--provision cloud-init`, then `exec` as root. The `console` one tested: `exec` never answered in 200 s.

### Slackware

🚫 No aarch64 build of mainline Slackware. [The mirror](https://mirrors.slackware.com/slackware/) has only `slackware` and `slackware64` trees; Slackware ARM is a separate port that was not checked.

### Rocky Linux

```
terrarium run CLOUD_IMAGE --provision cloud-init
terrarium run ISO_IMAGE
```

| Variant | 🟧 10.3 staging[^rocky-staging] | 🟩 10.2 | 🟩 9.8 |
|---|---|---|---|
| Boot ISO (netinstall)[^el-installer] | ✅ [1.03 GB](https://dl.rockylinux.org/stg/rocky/10.3/isos/aarch64/Rocky-10-latest-aarch64-boot.iso) | ✅ [1.12 GB](https://download.rockylinux.org/pub/rocky/10/isos/aarch64/Rocky-10.2-aarch64-boot.iso) | ✅ [1.42 GB](https://download.rockylinux.org/pub/rocky/9/isos/aarch64/Rocky-9.8-aarch64-boot.iso) |
| Minimal ISO[^el-installer] | ✅ [1.60 GB](https://dl.rockylinux.org/stg/rocky/10.3/isos/aarch64/Rocky-10-latest-aarch64-minimal.iso) | ✅ [2.40 GB](https://download.rockylinux.org/pub/rocky/10/isos/aarch64/Rocky-10.2-aarch64-minimal.iso) | ✅ [2.53 GB](https://download.rockylinux.org/pub/rocky/9/isos/aarch64/Rocky-9.8-aarch64-minimal.iso) |
| DVD ISO[^el-installer] | ✅ [10.14 GB](https://dl.rockylinux.org/stg/rocky/10.3/isos/aarch64/Rocky-10-latest-aarch64-dvd.iso) | ✅ [9.66 GB](https://download.rockylinux.org/pub/rocky/10/isos/aarch64/Rocky-10.2-aarch64-dvd1.iso) | ✅ [13.02 GB](https://download.rockylinux.org/pub/rocky/9/isos/aarch64/Rocky-9.8-aarch64-dvd.iso) |
| GenericCloud-Base (qcow2)[^el-cloud] | ✅ [0.49 GB](https://dl.rockylinux.org/stg/rocky/10.3/images/aarch64/Rocky-10-GenericCloud-Base.latest.aarch64.qcow2) | ✅ [0.47 GB](https://download.rockylinux.org/pub/rocky/10/images/aarch64/Rocky-10-GenericCloud-Base.latest.aarch64.qcow2) | ✅ [0.52 GB](https://download.rockylinux.org/pub/rocky/9/images/aarch64/Rocky-9-GenericCloud-Base.latest.aarch64.qcow2) |
| GenericCloud-LVM (qcow2)[^el-cloud] | ✅ [0.49 GB](https://dl.rockylinux.org/stg/rocky/10.3/images/aarch64/Rocky-10-GenericCloud-LVM.latest.aarch64.qcow2) | ✅ [0.47 GB](https://download.rockylinux.org/pub/rocky/10/images/aarch64/Rocky-10-GenericCloud-LVM-10.2-20260525.0.aarch64.qcow2) | ✅ [0.53 GB](https://download.rockylinux.org/pub/rocky/9/images/aarch64/Rocky-9-GenericCloud-LVM-9.8-20260525.0.aarch64.qcow2) |

EC2, OCP, and Raspberry Pi images also exist, and are not listed. Rocky 8.10 is not listed; see [the AlmaLinux note](#almalinux) on Enterprise Linux 8.

[^rocky-staging]: A public staging tree (`dl.rockylinux.org/stg/rocky/10.3`) with `latest` aliases for the unreleased 10.3, not an official nightly channel. Tested: GenericCloud-Base and LVM (`--provision cloud-init`, then `exec` as root; Rocky Linux 10.3) and the boot and minimal ISOs (Anaconda's welcome page, marked "pre-release / testing").

### Deepin

```
terrarium run IMAGE
```

| Variant | 🟩 25.2.0 |
|---|---|
| Desktop ISO[^deepin] | ✅ [5.51 GB](https://cdimage.deepin.com/releases/25.2.0/arm64/deepin-desktop-community-25.2.0-arm64.iso) |

[^deepin]: From the release directory's listing; the ISO targets arm64 PCs; it boots under Virtualization to its boot menu (1920x1080), and went no further.

### Qubes OS

🚫 No aarch64 build. [The downloads page](https://www.qubes-os.org/downloads/) offers only `Qubes-R4.3.2-x86_64.iso`.

### Oracle Linux

```
terrarium run CLOUD_IMAGE --provision cloud-init
terrarium run ISO_IMAGE
```

| Variant | 🟩 10 | 🟩 9 |
|---|---|---|
| DVD ISO[^oracle] | ⬜ [10.54 GB](https://yum.oracle.com/ISOS/OracleLinux/OL10/u2/aarch64/OracleLinux-R10-U2-aarch64-dvd.iso) | ⬜ [14.19 GB](https://yum.oracle.com/ISOS/OracleLinux/OL9/u8/aarch64/OracleLinux-R9-U8-aarch64-dvd.iso) |
| boot-uek ISO | ✅ [1.55 GB](https://yum.oracle.com/ISOS/OracleLinux/OL10/u2/aarch64/OracleLinux-R10-U2-aarch64-boot-uek.iso) | ✅ [1.68 GB](https://yum.oracle.com/ISOS/OracleLinux/OL9/u8/aarch64/OracleLinux-R9-U8-aarch64-boot-uek.iso) |
| kvm-cloud (qcow2)[^oracle] | ✅ [0.75 GB](https://yum.oracle.com/templates/OracleLinux/OL10/u1/aarch64/OL10U1_aarch64-kvm-cloud-b178.qcow2) | ✅ [0.66 GB](https://yum.oracle.com/templates/OracleLinux/OL9/u8/aarch64/OL9U8_aarch64-kvm-cloud-b182.qcow2) |
| kvm (qcow2) | ✅ [1.42 GB](https://yum.oracle.com/templates/OracleLinux/OL10/u1/aarch64/OL10U1_aarch64-kvm-b177.qcow2) | ✅ [1.55 GB](https://yum.oracle.com/templates/OracleLinux/OL9/u8/aarch64/OL9U8_aarch64-kvm-b181.qcow2) |

[^oracle]: Downloads are anonymous. The ISOs are the newest updates (10 U2, 9 U8); the templates lag them (10 U1, 9 U8). Oracle Linux 8 is not listed; see [the AlmaLinux note](#almalinux) on Enterprise Linux 8. `kvm-cloud` carries cloud-init (the OL9 U8 image's README lists `cloud-init`), and `kvm` is the non-cloud image, which boots UEFI. UTM `.utm.zip` bundles also exist; `pull` does not take a zip, so they are not listed. 10 `kvm-cloud` and `kvm` tested: `--provision cloud-init`, then `exec` as root, on both (Oracle Linux Server 10.1); the plain `kvm` image answered too. The rest are untested. The 9 `kvm` image tested on 2026-11-09 the same way as the 10 one: `--provision cloud-init`, then `exec` as root (Oracle Linux Server 9.8).

### Amazon Linux 2023

DistroWatch does not rank Amazon Linux.

```
terrarium run IMAGE --provision cloud-init
```

| Variant | 🟩 2023 |
|---|---|
| KVM arm64 (qcow2)[^amazon] | ✅ [2.04 GB](https://cdn.amazonlinux.com/al2023/os-images/latest/kvm-arm64/al2023-kvm-2023.12.20261109.0-kernel-6.1-arm64.xfs.gpt.qcow2) |

[^amazon]: There is no ISO. The `os-images/` directory itself returns 403, but the files download anonymously from `latest/kvm-arm64/`, and the file name carries the build date. The image has no usable login until it is seeded; AWS's [guide to running it outside EC2](https://docs.aws.amazon.com/linux/al2023/ug/outside-ec2.html) supplies NoCloud seed data, which is what `--provision cloud-init` attaches. Tested: `--provision cloud-init`, then `exec` as root (Amazon Linux 2023.12.20261109, 2026-11-09).

## BSDs

FreeBSD, OpenBSD, and NetBSD publish generic aarch64 images that should boot under Virtualization's UEFI, listed in the same DistroWatch order, each below. terrarium's helper supports Linux, macOS, and Windows, so none of these has a helper: `--provision cloud-init` installs the Linux helper and does not apply. Drive them with `shot`, `click`, `type`, and `key`.

### FreeBSD

```
terrarium run IMAGE
```

| Variant | 🟧 16.0-CURRENT | 🟧 15.2-BETA1 | 🟩 15.1 | 🟫 14.5 |
|---|---|---|---|---|
| VM image, cloud-init (qcow2.xz)[^freebsd] | ❌ [0.62 GB](https://download.freebsd.org/snapshots/VM-IMAGES/16.0-CURRENT/aarch64/Latest/FreeBSD-16.0-CURRENT-arm64-aarch64-BASIC-CLOUDINIT-ufs.qcow2.xz) | ❌ [0.60 GB](https://download.freebsd.org/releases/VM-IMAGES/15.2-BETA1/aarch64/Latest/FreeBSD-15.2-BETA1-arm64-aarch64-BASIC-CLOUDINIT-ufs.qcow2.xz) | ❌ [0.59 GB](https://download.freebsd.org/releases/VM-IMAGES/15.1-RELEASE/aarch64/Latest/FreeBSD-15.1-RELEASE-arm64-aarch64-BASIC-CLOUDINIT-ufs.qcow2.xz) | ❌ [0.58 GB](https://download.freebsd.org/releases/VM-IMAGES/14.5-RELEASE/aarch64/Latest/FreeBSD-14.5-RELEASE-arm64-aarch64-BASIC-CLOUDINIT-ufs.qcow2.xz) |
| VM image (qcow2.xz)[^freebsd] | — | — | ❌ [0.59 GB](https://download.freebsd.org/releases/VM-IMAGES/15.1-RELEASE/aarch64/Latest/FreeBSD-15.1-RELEASE-arm64-aarch64-ufs.qcow2.xz) | — |
| Bootonly ISO | — | — | ❌ [0.46 GB](https://download.freebsd.org/releases/ISO-IMAGES/15.1/FreeBSD-15.1-RELEASE-arm64-aarch64-bootonly.iso) | — |
| disc1 ISO | — | — | ❌ [1.20 GB](https://download.freebsd.org/releases/ISO-IMAGES/15.1/FreeBSD-15.1-RELEASE-arm64-aarch64-disc1.iso) | ❌ [1.17 GB](https://download.freebsd.org/releases/ISO-IMAGES/14.5/FreeBSD-14.5-RELEASE-arm64-aarch64-disc1.iso) |
| dvd1 ISO | — | — | ❌ [4.30 GB](https://download.freebsd.org/releases/ISO-IMAGES/15.1/FreeBSD-15.1-RELEASE-arm64-aarch64-dvd1.iso) | — |

[^freebsd]: The `BASIC-CLOUDINIT` images use FreeBSD's `nuageinit`, not Python cloud-init, and have no default password; login comes from injected user-data or SSH keys. The plain VM images sign in as `root` with an empty password and run no sshd. FreeBSD 15.2 is in beta, and snapshots follow `Latest/` paths. The `.xz` files are single compressed disks, which `pull` decompresses. Tested on 15.1 with no helper (there is none for BSD): the cloud-init image's `--provision cloud-init` gave no `exec`, as expected, and the console log stayed empty. The plain VM image reached FreeBSD's boot menu and stopped at "Loading kernel" on the display after two minutes (the kernel may write to a serial console only). Every FreeBSD image tested (15.1, 14.5, 15.2-BETA1, and 16.0-CURRENT; ISOs, plain VM images, and cloud-init images) was left running two to eleven minutes, and none got past the loader: the 15.1 plain VM image still had not finished loading the kernel after 11 minutes (its `text=` and `data=` progress line crawls, about 21 KB/s, far slower than other guests read the same disk), and the 14.5 cloud-init image reached "Loading configured modules" and printed `can't find '/boot/entropy'` after 10 minutes. With four vCPUs the cause of the crawl was not found, but with `--cpus 1` the 15.1 plain VM image got through the loader in under three minutes and stopped at `No valid device tree blob found!`: VZ's firmware offers ACPI only, and 15.x needs a device tree, as [tjfontaine/freebsd-apple-virtualization](https://github.com/tjfontaine/freebsd-apple-virtualization) found (it boots a prepared 16.0-CURRENT guest with one vCPU, one console, and no USB keyboard or pointer, which terrarium cannot yet give a guest). The 16.0-CURRENT cloud-init image was still loading its kernel after ten minutes with one vCPU. The dvd1 ISO and the 14.5 ISOs not named here are untested. The 15.1 dvd1 ISO tested on 2026-11-09: after about 170 s the display still showed the loader's menu (*Welcome to FreeBSD*, 1. Boot Installer), so it fares as the others do (❌).

### OpenBSD

```
terrarium run IMAGE
```

| Variant | 🟩 8.0 |
|---|---|
| Install image (img)[^openbsd] | ✅ [0.73 GB](https://cdn.openbsd.org/pub/OpenBSD/8.0/arm64/install80.img) |
| Install ISO[^openbsd] | ✅ [0.66 GB](https://cdn.openbsd.org/pub/OpenBSD/8.0/arm64/install80.iso) |
| Miniroot (img)[^openbsd] | ✅ [0.05 GB](https://cdn.openbsd.org/pub/OpenBSD/8.0/arm64/miniroot80.img) |

[^openbsd]: Installers: set the root password during the install. The 8.0 install ISO reaches the same installation program prompt as the miniroot. There are no cloud-init images. The 8.0 miniroot tested: it boots to the installation program's `(I)nstall, (U)pgrade, (A)utoinstall or (S)hell?` prompt on the display. The 8.0 install image tested on 2026-11-09 the same way: it reaches the installation program's prompt, as the miniroot does.

### NetBSD

```
terrarium run IMAGE
```

| Variant | 🟩 11.1 |
|---|---|
| evbarm-aarch64 ISO[^netbsd] | ⬜ [0.30 GB](https://cdn.netbsd.org/pub/NetBSD/images/11.1/NetBSD-11.1-evbarm-aarch64.iso) |
| Install image (img.gz)[^netbsd] | ⬜ [0.95 GB](https://cdn.netbsd.org/pub/NetBSD/images/11.1/NetBSD-11.1-evbarm-aarch64-install.img.gz) |
| Prebuilt disk (img.gz)[^netbsd] | ⬜ [0.44 GB](https://cdn.netbsd.org/pub/NetBSD/NetBSD-11.1/evbarm-aarch64/binary/gzimg/arm64.img.gz) |

[^netbsd]: There is no cloud-init. The prebuilt `arm64.img.gz` is a ready-to-boot disk, not an installer (a `gzip`, not `xz`, file; `pull` decompresses both), and the `.iso` and `-install.img.gz` are installers. Tested, not marked: the prebuilt disk booted to NetBSD's efiboot and printed "booting netbsd", and the ISO to its installation CD menu, "loading ramdisk.fs"; both screens stopped there after two minutes (the kernel may write to a serial console only). On 2026-11-09 the downloads from cdn.netbsd.org timed out, and tried again two of them timed out once more (the ISO and the install image), so those are untested; the prebuilt disk came down on the second try and stopped at the same efiboot screen as before.

## macOS

Restore images (IPSW) for the virtual Mac, from [ipsw.me](https://api.ipsw.me/v4/device/VirtualMac2,1?type=ipsw), which lists 60 of them from 12.4 to 27.2. This table keeps the newest of each major version, plus 27.0 and 26.0. All are on `updates.cdn-apple.com` and answered HTTP 200.

```
terrarium run IPSW_IMAGE --install macos --user NAME --accept-license \
  --tweak no-sleep --tweak no-screensaver --tweak quiet-setup
```

| macOS | Build | Status | Image |
|---|---|---|---|
| 🟧 Beta or seed[^macos-beta] | | 🚫 | none found |
| 🟩 macOS 27 (27.2) | 26B123 | ✅ | [25.6 GB](https://updates.cdn-apple.com/2026FallFCS/c9671975-52db-4fb5-9af2-00217169ba8d/UniversalMac_27.2_26B123_Restore.ipsw) |
| 🟩 macOS 27 (27.0) | 26A428 | ⬜ | [26.6 GB](https://updates.cdn-apple.com/2026FallFCS/afcfc88e-bbe6-44bf-a5da-07c56eebc06c/UniversalMac_27.0_26A428_Restore.ipsw) |
| 🟩 macOS 26 (26.6.2) | 25G83 | ⬜ | [19.8 GB](https://updates.cdn-apple.com/2026SummerFCS/fullrestores/140-75212/A2A24B94-1FC1-45A3-93F7-C51B02AF1F4D/UniversalMac_26.6.2_25G83_Restore.ipsw) |
| 🟫 macOS 26 (26.0) | 25A354 | ⬜ | [18.3 GB](https://updates.cdn-apple.com/2025FallFCS/fullrestores/093-37622/CE01FAB2-7F26-48EE-AEE4-5E57A7F6D8BB/UniversalMac_26.0_25A354_Restore.ipsw) |
| 🟫 Sequoia 15 (15.6.1) | 24G90 | ⬜ | [16.8 GB](https://updates.cdn-apple.com/2025SummerFCS/fullrestores/093-10809/CFD6DD38-DAF0-40DA-854F-31AAD1294C6F/UniversalMac_15.6.1_24G90_Restore.ipsw) |
| 🟫 Sonoma 14 (14.6.1) | 23G93 | ⬜ | [14.8 GB](https://updates.cdn-apple.com/2024SummerFCS/fullrestores/062-52859/932E0A8F-6644-4759-82DA-F8FA8DEA806A/UniversalMac_14.6.1_23G93_Restore.ipsw) |
| 🟫 Ventura 13 (13.6) | 22G120 | ⬜ | [12.9 GB](https://updates.cdn-apple.com/2023FallFCS/fullrestores/042-55833/C0830847-A2F8-458F-B680-967991820931/UniversalMac_13.6_22G120_Restore.ipsw) |
| 🟫 Monterey 12 (12.6) | 21G115 | ⬜ | [14.1 GB](https://updates.cdn-apple.com/2022FallFCS/fullrestores/012-40537/0EC7C669-13E9-49FB-BD64-9EECC1D174B2/UniversalMac_12.6_21G115_Restore.ipsw) |

27.2 tested: `--install macos --user NAME --accept-license` (the helper goes in over SSH), `exec`, `shot`, `click`, and the macOS Send Key chords. [^macos]

[^macos-beta]: ipsw.me lists release builds only, and no beta or seed IPSW has a URL that can be pulled without an Apple developer account. Untested.
[^macos]: Recipe `--install macos`; tweaks `macos/no-sleep`, `macos/no-screensaver`, and `macos/quiet-setup`. The other versions are untested, including whether Virtualization on a macOS 27 host accepts each guest. ipsw.me's `signed` flag is false for every entry, so it does not say which images Apple still signs; the CDN serves them all.

## Windows

Microsoft publishes no stable URL for an ARM64 image. The download page makes a link that lives about 24 hours, so save the ISO and `pull` the file, as the [Windows guide](windows.md) does. The page offers only the current release (26H2 on 2026-11-08), as one multi-edition ISO in each language; older builds are not offered.

```
terrarium run ISO_IMAGE --install windows --accept-license
terrarium run PATH.guest --tweak edge-quiet --tweak no-sleep --tweak no-lock
```

| Release | Where to get it | Status |
|---|---|---|
| Windows 11 ARM64, build 26300 | [The ARM64 download page](https://www.microsoft.com/en-us/software-download/windows11arm64) | ✅ `pull` of the saved ISO, then `--install windows`[^windows] |
| Windows 11 Enterprise evaluation | [The evaluation center](https://www.microsoft.com/en-us/evalcenter/download-windows-11-enterprise) | 🚫 behind a registration form; an ARM64 ISO was not confirmed |
| Windows 10 ARM64 | none found | 🚫 |
| Windows Server 2022 and 2025 ARM64 | none found | 🚫 Microsoft is reported not to ship an ARM64 Server ISO |
| Windows Insider Preview ARM64 | [The Insider page](https://www.microsoft.com/en-us/software-download/windowsinsiderpreviewARM64) | 🚫 needs an Insider sign-in |

[^windows]: Build 26300 tested: `--install windows` (unattended install, the helper as an at-logon task), `commit --on-stop`, a boot of the saved guest with the ISO removed, `exec`, input through `key` and `type`, and the license page. Tweaks: `windows/edge-quiet`, `windows/no-sleep`, and `windows/no-lock`.

## Sources

Every image link above comes from the vendor's own download page, release directory, or API, found there on 2026-11-09 and checked with `HEAD`. Evidence for a missing aarch64 build is linked in that distribution's section. Statements marked as from memory (openSUSE's image definitions) were not checked.

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
