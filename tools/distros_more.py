# Included by distros.py (exec'd in its namespace): Red Hat family, openSUSE, specialty, and BSD data.

# ---------- Red Hat family
RK = "https://download.rockylinux.org/pub/rocky"
rocky_cols = ["10.3 staging", "10.2", "9.8"]
STG = "https://dl.rockylinux.org/stg/rocky/10.3"


def rocky(fmt, stg=None):
    d = {c: f"{RK}/" + fmt.format(m=c.split(".")[0], v=c) for c in rocky_cols if c != "10.3 staging"}
    d["10.3 staging"] = f"{STG}/{stg}" if stg else "-"
    return d


rocky_rows = [
    ("Boot ISO (netinstall)", rocky("{m}/isos/aarch64/Rocky-{v}-aarch64-boot.iso", "isos/aarch64/Rocky-10-latest-aarch64-boot.iso")),
    ("Minimal ISO", rocky("{m}/isos/aarch64/Rocky-{v}-aarch64-minimal.iso", "isos/aarch64/Rocky-10-latest-aarch64-minimal.iso")),
    ("DVD ISO", {"10.3 staging": f"{STG}/isos/aarch64/Rocky-10-latest-aarch64-dvd.iso",
                 "10.2": f"{RK}/10/isos/aarch64/Rocky-10.2-aarch64-dvd1.iso",
                 "9.8": f"{RK}/9/isos/aarch64/Rocky-9.8-aarch64-dvd.iso"}),
    ("GenericCloud-Base (qcow2)", {"10.3 staging": f"{STG}/images/aarch64/Rocky-10-GenericCloud-Base.latest.aarch64.qcow2",
                                   "10.2": f"{RK}/10/images/aarch64/Rocky-10-GenericCloud-Base.latest.aarch64.qcow2",
                                   "9.8": f"{RK}/9/images/aarch64/Rocky-9-GenericCloud-Base.latest.aarch64.qcow2"}),
    ("GenericCloud-LVM (qcow2)", {"10.3 staging": f"{STG}/images/aarch64/Rocky-10-GenericCloud-LVM.latest.aarch64.qcow2",
                                  "10.2": f"{RK}/10/images/aarch64/Rocky-10-GenericCloud-LVM-10.2-20260525.0.aarch64.qcow2",
                                  "9.8": f"{RK}/9/images/aarch64/Rocky-9-GenericCloud-LVM-9.8-20260525.0.aarch64.qcow2"}),
]
AM = "https://repo.almalinux.org/almalinux"
alma_cols = ["Kitten 10", "10.2", "9.8"]
KIT = "https://repo.almalinux.org/almalinux-kitten/10-kitten"


def alma(fmt, only=None, gone=(), kitten=None):
    d = {}
    for c in alma_cols:
        m = c.split(".")[0]
        if c == "Kitten 10":
            d[c] = f"{KIT}/{kitten}" if kitten else "-"
        elif c in gone:
            d[c] = None
        elif only and c not in only:
            d[c] = "-"
        else:
            d[c] = f"{AM}/" + fmt.format(m=m, v=c)
    return d


alma_rows = [
    ("Boot ISO (netinstall)", alma("{m}/isos/aarch64/AlmaLinux-{v}-aarch64-boot.iso", kitten="isos/aarch64/AlmaLinux-Kitten-10-latest-aarch64-boot.iso")),
    ("Minimal ISO", alma("{m}/isos/aarch64/AlmaLinux-{v}-aarch64-minimal.iso", kitten="isos/aarch64/AlmaLinux-Kitten-10-latest-aarch64-minimal.iso")),
    ("DVD ISO", alma("{m}/isos/aarch64/AlmaLinux-{v}-aarch64-dvd.iso", kitten="isos/aarch64/AlmaLinux-Kitten-10-latest-aarch64-dvd.iso")),
    ("Live GNOME ISO", alma("{m}/live/aarch64/AlmaLinux-{v}-aarch64-Live-GNOME.iso", only=("10.2", "9.8"), kitten="live/aarch64/AlmaLinux-Kitten-10-latest-aarch64-Live-GNOME.iso")),
    ("Live KDE ISO", alma("{m}/live/aarch64/AlmaLinux-{v}-aarch64-Live-KDE.iso", only=("10.2", "9.8"), kitten="live/aarch64/AlmaLinux-Kitten-10-latest-aarch64-Live-KDE.iso")),
    ("Live MATE ISO", alma("{m}/live/aarch64/AlmaLinux-{v}-aarch64-Live-MATE.iso", only=("10.2", "9.8"), gone=("10.2",))),
    ("Live XFCE ISO", alma("{m}/live/aarch64/AlmaLinux-{v}-aarch64-Live-XFCE.iso", only=("10.2", "9.8"), gone=("10.2",))),
    ("GenericCloud (qcow2)", alma("{m}/cloud/aarch64/images/AlmaLinux-{m}-GenericCloud-latest.aarch64.qcow2", kitten="cloud/aarch64/images/AlmaLinux-Kitten-GenericCloud-10-latest.aarch64.qcow2")),
    ("GenericCloud ext4 (qcow2)", alma("{m}/cloud/aarch64/images/AlmaLinux-{m}-GenericCloud-ext4-latest.aarch64.qcow2", kitten="cloud/aarch64/images/AlmaLinux-Kitten-GenericCloud-ext4-10-latest.aarch64.qcow2")),
]
CS = "https://cloud.centos.org/centos"
CM = "https://mirror.stream.centos.org"
cs_cols = ["10", "9"]
centos_rows = [
    ("Boot ISO", {c: f"{CM}/{c}-stream/BaseOS/aarch64/iso/CentOS-Stream-{c}-latest-aarch64-boot.iso" for c in cs_cols}),
    ("DVD ISO", {c: f"{CM}/{c}-stream/BaseOS/aarch64/iso/CentOS-Stream-{c}-latest-aarch64-dvd1.iso" for c in cs_cols}),
    ("GenericCloud (qcow2)", {c: f"{CS}/{c}-stream/aarch64/images/CentOS-Stream-GenericCloud-{c}-latest.aarch64.qcow2" for c in cs_cols}),
    ("ec2 (raw.xz)", {c: f"{CS}/{c}-stream/aarch64/images/CentOS-Stream-ec2-{c}-latest.aarch64.raw.xz" for c in cs_cols}),
]
OR = "https://yum.oracle.com"
ol_cols = ["10", "9"]
ol_u = {"10": ("u2", "R10-U2"), "9": ("u8", "R9-U8")}
ol_t = {"10": ("u1", "OL10U1", "178", "177"), "9": ("u8", "OL9U8", "182", "181")}
oracle_rows = [
    ("DVD ISO", {c: f"{OR}/ISOS/OracleLinux/OL{c}/{ol_u[c][0]}/aarch64/OracleLinux-{ol_u[c][1]}-aarch64-dvd.iso" for c in ol_cols}),
    ("boot-uek ISO", {c: f"{OR}/ISOS/OracleLinux/OL{c}/{ol_u[c][0]}/aarch64/OracleLinux-{ol_u[c][1]}-aarch64-boot-uek.iso" for c in ol_cols}),
    ("kvm-cloud (qcow2)", {c: f"{OR}/templates/OracleLinux/OL{c}/{ol_t[c][0]}/aarch64/{ol_t[c][1]}_aarch64-kvm-cloud-b{ol_t[c][2]}.qcow2" for c in ol_cols}),
    ("kvm (qcow2)", {c: f"{OR}/templates/OracleLinux/OL{c}/{ol_t[c][0]}/aarch64/{ol_t[c][1]}_aarch64-kvm-b{ol_t[c][3]}.qcow2" for c in ol_cols}),
]
AL2023 = "https://cdn.amazonlinux.com/al2023/os-images/latest/kvm-arm64/al2023-kvm-2023.12.20261109.0-kernel-6.1-arm64.xfs.gpt.qcow2"

# ---------- openSUSE
OL = "https://download.opensuse.org/distribution/leap"
OT = "https://download.opensuse.org/ports/aarch64/tumbleweed"
OM = "https://download.opensuse.org/distribution/leap-micro/6.2"
suse_cols = ["Tumbleweed", "Leap 16.1", "Leap 16.0", "Leap 15.6"]


def sl(l161, l160, l156, tw):
    return {"Leap 16.1": l161, "Leap 16.0": l160, "Leap 15.6": l156, "Tumbleweed": tw}


def lp(v, path):
    return f"{OL}/{v}/{path}"


suse_rows = [
    ("Offline installer ISO (DVD on 15.6)", sl(lp("16.1", "offline/Leap-16.1-offline-installer-aarch64.install.iso"),
                                                lp("16.0", "offline/Leap-16.0-offline-installer-aarch64.install.iso"),
                                                lp("15.6", "iso/openSUSE-Leap-15.6-DVD-aarch64-Current.iso"),
                                                f"{OT}/iso/openSUSE-Tumbleweed-DVD-aarch64-Current.iso")),
    ("Online installer ISO (NET on 15.6)", sl(lp("16.1", "offline/Leap-16.1-online-installer-aarch64.install.iso"),
                                              lp("16.0", "offline/Leap-16.0-online-installer-aarch64.install.iso"),
                                              lp("15.6", "iso/openSUSE-Leap-15.6-NET-aarch64-Current.iso"),
                                              f"{OT}/iso/openSUSE-Tumbleweed-NET-aarch64-Current.iso")),
    ("GNOME Live ISO", sl(None, None, "-", f"{OT}/iso/openSUSE-Tumbleweed-GNOME-Live-aarch64-Current.iso")),
    ("KDE Live ISO", sl(None, None, "-", f"{OT}/iso/openSUSE-Tumbleweed-KDE-Live-aarch64-Current.iso")),
    ("XFCE Live ISO", sl(None, None, "-", f"{OT}/iso/openSUSE-Tumbleweed-XFCE-Live-aarch64-Current.iso")),
    ("Minimal-VM kvm (qcow2)", sl(lp("16.1", "appliances/Leap-16.1-Minimal-VM.aarch64-kvm.qcow2"),
                                  lp("16.0", "appliances/Leap-16.0-Minimal-VM.aarch64-kvm.qcow2"),
                                  lp("15.6", "appliances/openSUSE-Leap-15.6-Minimal-VM.aarch64-kvm.qcow2"),
                                  f"{OT}/appliances/openSUSE-Tumbleweed-Minimal-VM.aarch64-kvm-and-xen.qcow2")),
    ("Minimal-VM Cloud (qcow2)", sl(lp("16.1", "appliances/Leap-16.1-Minimal-VM.aarch64-Cloud.qcow2"),
                                    lp("16.0", "appliances/Leap-16.0-Minimal-VM.aarch64-Cloud.qcow2"),
                                    lp("15.6", "appliances/openSUSE-Leap-15.6-Minimal-VM.aarch64-Cloud.qcow2"),
                                    f"{OT}/appliances/openSUSE-Tumbleweed-Minimal-VM.aarch64-Cloud.qcow2")),
    ("JeOS efi (qcow2)", sl("-", "-", lp("15.6", "appliances/openSUSE-Leap-15.6-ARM-JeOS-efi.aarch64.qcow2"),
                            f"{OT}/appliances/openSUSE-Tumbleweed-ARM-JeOS-efi.aarch64.qcow2")),
    ("KDE efi (raw.xz)", sl("-", "-", lp("15.6", "appliances/openSUSE-Leap-15.6-ARM-KDE-efi.aarch64.raw.xz"),
                            f"{OT}/appliances/openSUSE-Tumbleweed-ARM-KDE-efi.aarch64.raw.xz")),
    ("GNOME efi (raw.xz)", sl("-", "-", lp("15.6", "appliances/openSUSE-Leap-15.6-ARM-GNOME-efi.aarch64.raw.xz"),
                              f"{OT}/appliances/openSUSE-Tumbleweed-ARM-GNOME-efi.aarch64.raw.xz")),
    ("XFCE efi (raw.xz)", sl("-", "-", lp("15.6", "appliances/openSUSE-Leap-15.6-ARM-XFCE-efi.aarch64.raw.xz"),
                             f"{OT}/appliances/openSUSE-Tumbleweed-ARM-XFCE-efi.aarch64.raw.xz")),
]
atomic_cols = ["MicroOS", "Leap Micro 6.2"]
atomic_rows = [
    ("Installer ISO", {"Leap Micro 6.2": f"{OM}/product/iso/openSUSE-Leap-Micro-6.2-aarch64.iso",
                       "MicroOS": f"{OT}/iso/openSUSE-MicroOS-DVD-aarch64-Current.iso"}),
    ("Disk image (qcow2)", {"Leap Micro 6.2": f"{OM}/appliances/openSUSE-Leap-Micro.aarch64-Default-qcow.qcow2",
                            "MicroOS": f"{OT}/appliances/openSUSE-MicroOS.aarch64-kvm-and-xen.qcow2"}),
    ("Cloud image (qcow2)", {"Leap Micro 6.2": "-", "MicroOS": f"{OT}/appliances/openSUSE-MicroOS.aarch64-OpenStack-Cloud.qcow2"}),
]

# ---------- flat tables: (distribution, release, variant, url); [^x] in a variant is a footnote mark
G = "https://distfiles.gentoo.org/releases/arm64/autobuilds/20261101T233055Z"
FB_ = "https://download.freebsd.org"
specialty = [
    ("Kali Linux", "2026.3", "Installer ISO (offline)", "https://cdimage.kali.org/kali-2026.3/kali-linux-2026.3-installer-arm64.iso"),
    ("Kali Linux", "2026.3", "Netinst ISO", "https://cdimage.kali.org/kali-2026.3/kali-linux-2026.3-installer-netinst-arm64.iso"),
    ("Kali Linux", "2026.3", "Cloud generic (tar.xz)[^kali]", "https://kali.download/cloud-images/kali-2026.3/kali-linux-2026.3-cloud-genericcloud-arm64.tar.xz"),
    ("Kali Linux", "2026-W46 (weekly)", "Installer ISO (offline)", "https://cdimage.kali.org/kali-weekly/kali-linux-2026-W46-installer-arm64.iso"),
    ("Kali Linux", "2026-W46 (weekly)", "Netinst ISO", "https://cdimage.kali.org/kali-weekly/kali-linux-2026-W46-installer-netinst-arm64.iso"),
    ("Parrot OS", "7.4", "Home ISO", "https://deb.parrot.sh/parrot/iso/7.4/Parrot-home-7.4_arm64.iso"),
    ("Parrot OS", "7.4", "Security ISO", "https://deb.parrot.sh/parrot/iso/7.4/Parrot-security-7.4_arm64.iso"),
    ("NixOS", "26.05", "Minimal ISO", "https://channels.nixos.org/nixos-26.05/latest-nixos-minimal-aarch64-linux.iso"),
    ("NixOS", "26.05", "Graphical ISO", "https://channels.nixos.org/nixos-26.05/latest-nixos-graphical-aarch64-linux.iso"),
    ("NixOS", "unstable", "Minimal ISO", "https://channels.nixos.org/nixos-unstable/latest-nixos-minimal-aarch64-linux.iso"),
    ("NixOS", "unstable", "Graphical ISO", "https://channels.nixos.org/nixos-unstable/latest-nixos-graphical-aarch64-linux.iso"),
    ("Gentoo", "rolling (20261101)", "Minimal install ISO[^gentoo]", f"{G}/install-arm64-minimal-20261101T233055Z.iso"),
    ("Gentoo", "rolling (20261101)", "Disk image, cloud-init (qcow2)[^gentoo]", f"{G}/di-arm64-cloudinit-20261101T233055Z.qcow2"),
    ("Gentoo", "rolling (20261101)", "Disk image, console (qcow2)[^gentoo]", f"{G}/di-arm64-console-20261101T233055Z.qcow2"),
    ("Void Linux", "20250202", "Live base ISO (glibc)[^void]", "https://repo-default.voidlinux.org/live/current/void-live-aarch64-20250202-base.iso"),
    ("Void Linux", "20250202", "Live Xfce ISO (glibc)[^void]", "https://repo-default.voidlinux.org/live/current/void-live-aarch64-20250202-xfce.iso"),
    ("Deepin", "25.2.0", "Desktop ISO[^deepin]", "https://cdimage.deepin.com/releases/25.2.0/arm64/deepin-desktop-community-25.2.0-arm64.iso"),
]
bsd = [
    ("FreeBSD", "16.0-CURRENT", "VM image, cloud-init (qcow2.xz)[^freebsd]", f"{FB_}/snapshots/VM-IMAGES/16.0-CURRENT/aarch64/Latest/FreeBSD-16.0-CURRENT-arm64-aarch64-BASIC-CLOUDINIT-ufs.qcow2.xz"),
    ("FreeBSD", "15.2-BETA1", "VM image, cloud-init (qcow2.xz)[^freebsd]", f"{FB_}/releases/VM-IMAGES/15.2-BETA1/aarch64/Latest/FreeBSD-15.2-BETA1-arm64-aarch64-BASIC-CLOUDINIT-ufs.qcow2.xz"),
    ("FreeBSD", "15.1", "VM image, cloud-init (qcow2.xz)[^freebsd]", f"{FB_}/releases/VM-IMAGES/15.1-RELEASE/aarch64/Latest/FreeBSD-15.1-RELEASE-arm64-aarch64-BASIC-CLOUDINIT-ufs.qcow2.xz"),
    ("FreeBSD", "15.1", "VM image (qcow2.xz)[^freebsd]", f"{FB_}/releases/VM-IMAGES/15.1-RELEASE/aarch64/Latest/FreeBSD-15.1-RELEASE-arm64-aarch64-ufs.qcow2.xz"),
    ("FreeBSD", "15.1", "Bootonly ISO", f"{FB_}/releases/ISO-IMAGES/15.1/FreeBSD-15.1-RELEASE-arm64-aarch64-bootonly.iso"),
    ("FreeBSD", "15.1", "disc1 ISO", f"{FB_}/releases/ISO-IMAGES/15.1/FreeBSD-15.1-RELEASE-arm64-aarch64-disc1.iso"),
    ("FreeBSD", "15.1", "dvd1 ISO", f"{FB_}/releases/ISO-IMAGES/15.1/FreeBSD-15.1-RELEASE-arm64-aarch64-dvd1.iso"),
    ("FreeBSD", "14.5", "VM image, cloud-init (qcow2.xz)[^freebsd]", f"{FB_}/releases/VM-IMAGES/14.5-RELEASE/aarch64/Latest/FreeBSD-14.5-RELEASE-arm64-aarch64-BASIC-CLOUDINIT-ufs.qcow2.xz"),
    ("FreeBSD", "14.5", "disc1 ISO", f"{FB_}/releases/ISO-IMAGES/14.5/FreeBSD-14.5-RELEASE-arm64-aarch64-disc1.iso"),
    ("OpenBSD", "8.0", "Install image (img)[^openbsd]", "https://cdn.openbsd.org/pub/OpenBSD/8.0/arm64/install80.img"),
    ("OpenBSD", "8.0", "Install ISO[^openbsd]", "https://cdn.openbsd.org/pub/OpenBSD/8.0/arm64/install80.iso"),
    ("OpenBSD", "8.0", "Miniroot (img)[^openbsd]", "https://cdn.openbsd.org/pub/OpenBSD/8.0/arm64/miniroot80.img"),
    ("NetBSD", "11.1", "evbarm-aarch64 ISO[^netbsd]", "https://cdn.netbsd.org/pub/NetBSD/images/11.1/NetBSD-11.1-evbarm-aarch64.iso"),
    ("NetBSD", "11.1", "Install image (img.gz)[^netbsd]", "https://cdn.netbsd.org/pub/NetBSD/images/11.1/NetBSD-11.1-evbarm-aarch64-install.img.gz"),
    ("NetBSD", "11.1", "Prebuilt disk (img.gz)[^netbsd]", "https://cdn.netbsd.org/pub/NetBSD/NetBSD-11.1/evbarm-aarch64/binary/gzimg/arm64.img.gz"),
]
# tested, and working or not (the cause is in the variant's footnote)
TESTED_FLAT = {
    ("Kali Linux", "2026.3", "Cloud generic (tar.xz)"),
    ("Gentoo", "rolling (20261101)", "Disk image, cloud-init (qcow2)"),
    ("OpenBSD", "8.0", "Miniroot (img)"),
    ("Kali Linux", "2026.3", "Installer ISO (offline)"),
    ("Kali Linux", "2026.3", "Netinst ISO"),
    ("Gentoo", "rolling (20261101)", "Minimal install ISO"),
    ("NixOS", "26.05", "Minimal ISO"),
    ("NixOS", "26.05", "Graphical ISO"),
    ("Void Linux", "20250202", "Live base ISO (glibc)"),
    ("Void Linux", "20250202", "Live Xfce ISO (glibc)"),
    ("Parrot OS", "7.4", "Home ISO"),
    ("Deepin", "25.2.0", "Desktop ISO"),
    ("Amazon Linux 2023", "2023", "KVM arm64 (qcow2)"),
    ("elementary OS", "8.1.1", "Desktop ISO"),
    ("Pop!_OS", "24.04 LTS", "ARM generic ISO"),
    ("Pop!_OS", "24.04 LTS", "ARM NVIDIA ISO"),
    ("OpenBSD", "8.0", "Install ISO"),
    ("NixOS", "unstable", "Minimal ISO"),
    ("NixOS", "unstable", "Graphical ISO"),
    ("Kali Linux", "2026-W46 (weekly)", "Installer ISO (offline)"),
    ("Kali Linux", "2026-W46 (weekly)", "Netinst ISO"),
    ('OpenBSD', '8.0', 'Install image (img)'),
}
BAD_FLAT = {
    ("Gentoo", "rolling (20261101)", "Disk image, console (qcow2)"),
    ("FreeBSD", "15.1", "VM image (qcow2.xz)"),
    ('FreeBSD', '15.1', 'VM image, cloud-init (qcow2.xz)'),
    ('FreeBSD', '15.1', 'Bootonly ISO'),
    ('FreeBSD', '15.1', 'disc1 ISO'),
    ('FreeBSD', '14.5', 'VM image, cloud-init (qcow2.xz)'),
    ('FreeBSD', '14.5', 'disc1 ISO'),
    ('FreeBSD', '15.2-BETA1', 'VM image, cloud-init (qcow2.xz)'),
    ('FreeBSD', '16.0-CURRENT', 'VM image, cloud-init (qcow2.xz)'),
    ('FreeBSD', '15.1', 'dvd1 ISO'),
}


def flat(rows, with_dist=True):
    head_row = "| Distribution | Release | Variant | Image |" if with_dist else "| Release | Variant | Image |"
    out = [head_row, "|---|---|---|---|" if with_dist else "|---|---|---|"]
    for dist, rel, var, url in rows:
        status, size = head(url)
        lead = f"{dist} | " if with_dist else ""
        if status != 200:
            FAILED.append(("flat", dist, var, url, status))
            out.append(f"| {lead}{rel} | {var} | ⚠️ {status} |")
            continue
        key = (dist, rel, re.sub(r"\[\^.*?\]", "", var))
        mark = OK if key in TESTED_FLAT else BAD if key in BAD_FLAT else UNTESTED
        out.append(f"| {lead}{rel} | {var} | {mark} [{size / 1e9:.2f} GB]({url}) |")
    return "\n".join(out)


# pivoted tables: releases are columns (newest to oldest), variants rows; the square says which use case a column serves
PIVOT_GROUP = {
    ("Kali Linux", "2026-W46 (weekly)"): EDGE, ("Kali Linux", "2026.3"): EVERYDAY,
    ("NixOS", "unstable"): EDGE, ("NixOS", "26.05"): EVERYDAY,
    ("Gentoo", "rolling (20261101)"): EVERYDAY, ("Void Linux", "20250202"): EVERYDAY,
    ("Parrot OS", "7.4"): EVERYDAY, ("Pop!_OS", "24.04 LTS"): EVERYDAY,
    ("FreeBSD", "16.0-CURRENT"): EDGE, ("FreeBSD", "15.2-BETA1"): EDGE, ("FreeBSD", "15.1"): EVERYDAY,
    ("FreeBSD", "14.5"): BEHIND, ("OpenBSD", "8.0"): EVERYDAY, ("NetBSD", "11.1"): EVERYDAY, ("Deepin", "25.2.0"): EVERYDAY, ("Amazon Linux 2023", "2023"): EVERYDAY,
}
PIVOT_NOTE = {("Kali Linux", "2026-W46 (weekly)"): "[^kali-weekly]"}


def pivot(rows):
    """rows: (distribution, release, variant, url) of one distribution -> a table of variants by release."""
    rels = []
    for dist, rel, _, _ in rows:
        if rel not in rels:
            rels.append(rel)
    rels.sort(key=lambda r: PIVOT_GROUP.get((rows[0][0], r)) != EDGE)  # stable: the 🟧 columns first
    heads = [f"{PIVOT_GROUP.get((rows[0][0], r), '')} {r}{PIVOT_NOTE.get((rows[0][0], r), '')}".strip() for r in rels]
    out = ["| Variant | " + " | ".join(heads) + " |", "|---|" + "---|" * len(rels)]
    variants = []
    for _, _, var, _ in rows:
        if var not in variants:
            variants.append(var)
    for var in variants:
        cells = []
        for rel in rels:
            hit = [r for r in rows if r[1] == rel and r[2] == var]
            if not hit:
                cells.append("—")
                continue
            dist, _, _, url = hit[0]
            status, size = head(url)
            if status != 200:
                FAILED.append(("flat", dist, var, url, status))
                cells.append(f"⚠️ {status}")
                continue
            key = (dist, rel, re.sub(r"\[\^.*?\]", "", var))
            mark = OK if key in TESTED_FLAT else BAD if key in BAD_FLAT else UNTESTED
            cells.append(f"{mark} [{size / 1e9:.2f} GB]({url})")
        out.append(f"| {var} | " + " | ".join(cells) + " |")
    return "\n".join(out)
