#!/usr/bin/env python3
"""Builds docs/distros.md from distros.template.md and the data here and in distros_more.py.

Usage: tools/distros.py [OUTPUT [TEMPLATE]]   (defaults: docs/distros.md, tools/distros.template.md)

Every image URL is HEAD-checked, and a failed one is reported, not written. The popularity ranking (RANKED) and the test
results (TESTED) are data kept by hand: update them when DistroWatch's ranking is read again or a test is run."""
import datetime, json, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "docs", "distros.md")
TEMPLATE_PATH = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "distros.template.md")
DATE = datetime.date.today().isoformat()  # when the URLs were checked
RANK_DATE = "2026-11-08"  # when DistroWatch's ranking in RANKED was read
CACHE = {}


def head(url):
    if url in CACHE:
        return CACHE[url]
    # A mirror behind a redirector can fail once; try again before calling a URL dead.
    for _ in range(3):
        r = subprocess.run(["curl", "-sIL", "-m", "45", url], capture_output=True, text=True)
        status, size = 0, None
        for line in r.stdout.splitlines():
            m = re.match(r"HTTP/\S+ (\d+)", line)
            if m:
                status = int(m.group(1))
            m = re.match(r"(?i)content-length:\s*(\d+)", line)
            if m:
                size = int(m.group(1))
        if status == 200:
            break
    CACHE[url] = (status, size)
    return CACHE[url]


EL_CLOUD = ("GenericCloud images carry cloud-init, and `--provision cloud-init` gives them the helper: tested on Rocky 10.2, "
            "10.3 staging, and 9.8 (also LVM), AlmaLinux 10.2, Kitten, and 9.8 (also ext4 images), and CentOS Stream 10 and 9 (also its ec2 image): "
            "`exec` as root, helper active.")
SUSE_CLOUD = ("Leap 16.1's `Cloud` image tested: `--provision cloud-init`, then `exec` as root. The `Cloud` and `OpenStack-Cloud` "
              "images are the cloud-init ones (that part is from memory of openSUSE's image definitions), so the others are "
              "expected to work the same; untested.")
KITTEN = ("Tested on 2026-11-08: the boot, minimal, Live GNOME, and Live KDE ISOs reach Anaconda's welcome page or the live session, "
          "and both GenericCloud images answer `exec` as root after `--provision cloud-init` (AlmaLinux Kitten 10).")
FAILED = []
OK, UNTESTED, NONE, BAD = "✅", "⬜", "🚫", "❌"
EVERYDAY, EDGE, BEHIND = "🟩", "🟧", "🟫"
# Which use case each column serves; edit here. Columns run newest to oldest.
GROUP = {
    ("ubuntu", "daily"): EDGE, ("ubuntu", "26.10"): EDGE, ("ubuntu", "26.04 LTS"): EVERYDAY,
    ("ubuntu", "24.04 LTS"): EVERYDAY, ("ubuntu", "22.04 LTS"): BEHIND,
    ("debian", "testing / 14 forky"): EDGE, ("debian", "13 trixie"): EVERYDAY,
    ("debian", "12 bookworm"): BEHIND, ("debian", "11 bullseye (LTS)"): BEHIND,
    ("fedora", "Rawhide"): EDGE, ("fedora", "45"): EVERYDAY, ("fedora", "44"): EVERYDAY, ("fedora", "43"): BEHIND,
    ("alpine", "edge"): EDGE, ("alpine", "3.24.4"): EVERYDAY, ("alpine", "3.23.8"): BEHIND,
    ("rocky", "10.3 staging"): EDGE, ("rocky", "10.2"): EVERYDAY, ("rocky", "9.8"): EVERYDAY,
    ("alma", "Kitten 10"): EDGE, ("alma", "10.2"): EVERYDAY, ("alma", "9.8"): EVERYDAY,
    ("centos", "10"): EDGE, ("centos", "9"): EVERYDAY,
    ("oracle", "10"): EVERYDAY, ("oracle", "9"): EVERYDAY,
    ("suse", "Tumbleweed"): EDGE, ("suse", "Leap 16.1"): EVERYDAY, ("suse", "Leap 16.0"): BEHIND, ("suse", "Leap 15.6"): BEHIND,
    ("atomic", "MicroOS"): EDGE, ("atomic", "Leap Micro 6.2"): EVERYDAY,
}
COLNOTE = {
    ("ubuntu", "daily"): "[^ubuntu-daily]", ("debian", "testing / 14 forky"): "[^debian-testing]",
    ("fedora", "Rawhide"): "[^fedora-rawhide]", ("alpine", "edge"): "[^alpine-edge]",
    ("rocky", "10.3 staging"): "[^rocky-staging]", ("alma", "Kitten 10"): "[^alma-kitten]",
}


def cell(table, row, col, url, tested):
    """A table cell: the status mark and a link whose text is the size."""
    if url is None:
        return NONE
    status, size = head(url)
    if status != 200:
        FAILED.append((table, row, col, url, status))
        return "⚠️ " + str(status)
    gb = "%.2f GB" % (size / 1e9) if size else "?"
    mark = OK if (table, row, col) in tested else BAD if (table, row, col) in TESTED_BAD else UNTESTED
    return "%s [%s](%s)" % (mark, gb, url)


def grid(table, cols, rows, tested, first="Variant"):
    """rows: (label, {col: url | None | '-'}). '-' is an empty cell. REFS adds a footnote mark to a row's label."""
    heads = ["%s %s%s" % (GROUP.get((table, c), ""), c, COLNOTE.get((table, c), "")) for c in cols]
    out = ["| %s | %s |" % (first, " | ".join(h.strip() for h in heads)), "|---|" + "---|" * len(cols)]
    for label, cells in rows:
        parts = []
        for c in cols:
            u = cells.get(c, "-")
            parts.append("—" if u == "-" else cell(table, label, c, u, tested))
        out.append("| %s%s | %s |" % (label, REFS.get((table, label), ""), " | ".join(parts)))
    return "\n".join(out)


REFS = {
    ("ubuntu", "Desktop ISO"): "[^ubuntu-desktop]",
    ("ubuntu", "Live server ISO"): "[^ubuntu-installer]",
    ("ubuntu", "Preinstalled server (img.xz)"): "[^ubuntu-installer]",
    ("ubuntu", "Cloud image"): "[^ubuntu-cloud]",
    ("ubuntu", "Minimal cloud image"): "[^ubuntu-cloud]",
    ("debian", "Cloud: genericcloud (qcow2)"): "[^debian-cloud]",
    ("debian", "Cloud: generic (qcow2)"): "[^debian-cloud]",
    ("debian", "Cloud: nocloud (qcow2)"): "[^debian-nocloud]",
    ("debian", "Installer: netinst ISO"): "[^debian-installer]",
    ("debian", "Installer: DVD-1 ISO"): "[^debian-installer]",
    ("debian", "Live GNOME ISO"): "[^debian-live]",
    ("fedora", "Workstation Live ISO"): "[^fedora-live]",
    ("fedora", "Cloud Base (qcow2)"): "[^fedora-cloud]",
    ("fedora", "Cloud AmazonEC2 (raw.xz)"): "[^fedora-cloud]",
    ("fedora", "Minimal (raw.xz)"): "[^fedora-minimal]",
    ("fedora", "Server netinst ISO"): "[^fedora-installer]",
    ("fedora", "Everything netinst ISO"): "[^fedora-installer]",
    ("fedora", "Silverblue installer ISO"): "[^fedora-atomic]",
    ("fedora", "Kinoite installer ISO"): "[^fedora-atomic]",
    ("fedora", "COSMIC Atomic installer ISO"): "[^fedora-atomic]",
    ("fedora", "IoT (raw.xz)"): "[^fedora-iot]",
    ("alpine", "Standard ISO"): "[^alpine-live]",
    ("alpine", "Virt ISO"): "[^alpine-live]",
    ("alpine", "Cloud, cloud-init (qcow2)"): "[^alpine-cloud]",
    ("alpine", "Cloud, Tiny Cloud (qcow2)"): "[^alpine-tiny]",
}


# ---------- what has been exercised: (table, row label, column)
TESTED = {
    ("ubuntu", "Desktop ISO", "26.04 LTS"),
    ("debian", "Cloud: genericcloud (qcow2)", "13 trixie"),
    ("fedora", "Cloud Base (qcow2)", "45"),
    ("fedora", "Cloud AmazonEC2 (raw.xz)", "44"),
    ("fedora", "Minimal (raw.xz)", "44"),
    ("fedora", "Workstation Live ISO", "44"),
    ("alpine", "Standard ISO", "3.24.4"),
    ("ubuntu", "Cloud image", "24.04 LTS"),
    ("debian", "Cloud: genericcloud (qcow2)", "12 bookworm"),
    ("rocky", "GenericCloud-Base (qcow2)", "10.2"),
    ("alma", "GenericCloud (qcow2)", "10.2"),
    ("centos", "GenericCloud (qcow2)", "10"),
    ("suse", "Minimal-VM Cloud (qcow2)", "Leap 16.1"),
    ("alpine", "Cloud, cloud-init (qcow2)", "3.24.4"),
    ("debian", "Cloud: generic (qcow2)", "13 trixie"),
    ("debian", "Installer: netinst ISO", "13 trixie"),
    ("ubuntu", "Cloud image", "26.04 LTS"),
    ("ubuntu", "Minimal cloud image", "26.04 LTS"),
    ("alpine", "Virt ISO", "3.24.4"),
    ("fedora", "Cloud UEFI-UKI (qcow2)", "45"),
    ("fedora", "Cloud AmazonEC2 (raw.xz)", "45"),
    ("rocky", "GenericCloud-LVM (qcow2)", "10.2"),
    ("alma", "GenericCloud ext4 (qcow2)", "10.2"),
    ("centos", "GenericCloud (qcow2)", "9"),
    ("centos", "ec2 (raw.xz)", "9"),
    ("oracle", "kvm-cloud (qcow2)", "10"),
    ("oracle", "kvm (qcow2)", "10"),
    ("atomic", "Disk image (qcow2)", "Leap Micro 6.2"),
    ("amazon", "", ""),
    ("debian", "Installer: DVD-1 ISO", "13 trixie"),
    ("debian", "Cloud: nocloud (qcow2)", "13 trixie"),
    ("debian", "Cloud: nocloud (qcow2)", "12 bookworm"),
    ("ubuntu", "Live server ISO", "26.04 LTS"),
    ("ubuntu", "Preinstalled server (img.xz)", "26.04 LTS"),
    ("fedora", "Server netinst ISO", "45"),
    ("fedora", "Everything netinst ISO", "45"),
    ("fedora", "KDE Plasma Live ISO", "45"),
    ("fedora", "Xfce Live ISO", "45"),
    ("fedora", "LXQt Live ISO", "45"),
    ("fedora", "i3 Live ISO", "45"),
    ("fedora", "COSMIC Live ISO", "45"),
    ("fedora", "KDE Mobile Live ISO", "45"),
    ("fedora", "SoaS Live ISO", "45"),
    ("fedora", "Python Classroom Live ISO", "45"),
    ("alma", "Boot ISO (netinstall)", "10.2"),
    ("alma", "Minimal ISO", "10.2"),
    ("alma", "Live GNOME ISO", "10.2"),
    ("alma", "Live KDE ISO", "10.2"),
    ("rocky", "Boot ISO (netinstall)", "10.2"),
    ("rocky", "Minimal ISO", "10.2"),
    ("centos", "Boot ISO", "9"),
    ("oracle", "boot-uek ISO", "10"),
    ("suse", "Online installer ISO (NET on 15.6)", "Leap 16.1"),
    ("pop", "ARM generic ISO", "24.04 LTS"),
    ('suse', 'JeOS efi (qcow2)', 'Tumbleweed'),
    ('suse', 'KDE efi (raw.xz)', 'Tumbleweed'),
    ('suse', 'KDE efi (raw.xz)', 'Leap 15.6'),
    ('suse', 'GNOME efi (raw.xz)', 'Tumbleweed'),
    ('suse', 'GNOME efi (raw.xz)', 'Leap 15.6'),
    ('suse', 'XFCE efi (raw.xz)', 'Tumbleweed'),
    ('suse', 'XFCE efi (raw.xz)', 'Leap 15.6'),
    ('suse', 'Offline installer ISO (DVD on 15.6)', 'Tumbleweed'),
    ('suse', 'Offline installer ISO (DVD on 15.6)', 'Leap 15.6'),
    ('atomic', 'Installer ISO', 'MicroOS'),
    ('pop', 'ARM NVIDIA ISO', '24.04 LTS'),
    ("fedora", "Workstation Live ISO", "45"),
    ("fedora", "MiracleWM Live ISO", "45"),
    ("fedora", "Silverblue installer ISO", "45"),
    ("fedora", "Kinoite installer ISO", "45"),
    ("fedora", "COSMIC Atomic installer ISO", "45"),
    ("suse", "Offline installer ISO (DVD on 15.6)", "Leap 16.1"),
    ('debian', 'Cloud: generic (qcow2)', '12 bookworm'),
    ('debian', 'Installer: netinst ISO', '12 bookworm'),
    ('debian', 'Installer: netinst ISO', '11 bullseye (LTS)'),
    ('fedora', 'Workstation Live ISO', '43'),
    ('fedora', 'Cloud Base (qcow2)', '44'),
    ('fedora', 'Cloud Base (qcow2)', '43'),
    ('fedora', 'Cloud UEFI-UKI (qcow2)', '44'),
    ('fedora', 'Cloud AmazonEC2 (raw.xz)', '43'),
    ('fedora', 'Server netinst ISO', '44'),
    ('fedora', 'Server netinst ISO', '43'),
    ('fedora', 'Everything netinst ISO', '44'),
    ('fedora', 'Everything netinst ISO', '43'),
    ('fedora', 'KDE Plasma Live ISO', '44'),
    ('fedora', 'KDE Plasma Live ISO', '43'),
    ('fedora', 'Xfce Live ISO', '44'),
    ('fedora', 'Xfce Live ISO', '43'),
    ('fedora', 'LXQt Live ISO', '44'),
    ('fedora', 'LXQt Live ISO', '43'),
    ('fedora', 'i3 Live ISO', '44'),
    ('fedora', 'i3 Live ISO', '43'),
    ('fedora', 'COSMIC Live ISO', '44'),
    ('fedora', 'COSMIC Live ISO', '43'),
    ('fedora', 'KDE Mobile Live ISO', '44'),
    ('fedora', 'KDE Mobile Live ISO', '43'),
    ('fedora', 'MiracleWM Live ISO', '44'),
    ('fedora', 'MiracleWM Live ISO', '43'),
    ('fedora', 'SoaS Live ISO', '44'),
    ('fedora', 'SoaS Live ISO', '43'),
    ('fedora', 'Silverblue installer ISO', '44'),
    ('fedora', 'Silverblue installer ISO', '43'),
    ('fedora', 'Kinoite installer ISO', '44'),
    ('fedora', 'Kinoite installer ISO', '43'),
    ('fedora', 'COSMIC Atomic installer ISO', '44'),
    ('fedora', 'COSMIC Atomic installer ISO', '43'),
    ('fedora', 'Python Classroom Live ISO', '44'),
    ('fedora', 'Python Classroom Live ISO', '43'),
    ('ubuntu', 'Desktop ISO', '24.04 LTS'),
    ('ubuntu', 'Live server ISO', '24.04 LTS'),
    ('ubuntu', 'Live server ISO', '22.04 LTS'),
    ('ubuntu', 'Preinstalled server (img.xz)', '24.04 LTS'),
    ('ubuntu', 'Cloud image', '22.04 LTS'),
    ('ubuntu', 'Minimal cloud image', '24.04 LTS'),
    ('suse', 'Offline installer ISO (DVD on 15.6)', 'Leap 16.0'),
    ('suse', 'Online installer ISO (NET on 15.6)', 'Leap 16.0'),
    ('suse', 'Online installer ISO (NET on 15.6)', 'Leap 15.6'),
    ('suse', 'Minimal-VM Cloud (qcow2)', 'Leap 16.0'),
    ('suse', 'Minimal-VM Cloud (qcow2)', 'Leap 15.6'),
    ('alpine', 'Standard ISO', '3.23.8'),
    ('alpine', 'Virt ISO', '3.23.8'),
    ('alpine', 'Cloud, cloud-init (qcow2)', '3.23.8'),
    ('alma', 'Boot ISO (netinstall)', '9.8'),
    ('alma', 'Minimal ISO', '9.8'),
    ('alma', 'Live GNOME ISO', '9.8'),
    ('alma', 'Live KDE ISO', '9.8'),
    ('alma', 'Live MATE ISO', '9.8'),
    ('alma', 'Live XFCE ISO', '9.8'),
    ('alma', 'GenericCloud (qcow2)', '9.8'),
    ('alma', 'GenericCloud ext4 (qcow2)', '9.8'),
    ('rocky', 'Boot ISO (netinstall)', '9.8'),
    ('rocky', 'Minimal ISO', '9.8'),
    ('rocky', 'GenericCloud-Base (qcow2)', '9.8'),
    ('rocky', 'GenericCloud-LVM (qcow2)', '9.8'),
    ('oracle', 'boot-uek ISO', '9'),
    ('oracle', 'kvm-cloud (qcow2)', '9'),
    ('debian', 'Cloud: genericcloud (qcow2)', 'testing / 14 forky'),
    ('debian', 'Cloud: generic (qcow2)', 'testing / 14 forky'),
    ('debian', 'Installer: netinst ISO', 'testing / 14 forky'),
    ('debian', 'Live GNOME ISO', 'testing / 14 forky'),
    ('fedora', 'Workstation Live ISO', 'Rawhide'),
    ('fedora', 'Cloud Base (qcow2)', 'Rawhide'),
    ('fedora', 'Cloud UEFI-UKI (qcow2)', 'Rawhide'),
    ('fedora', 'Cloud AmazonEC2 (raw.xz)', 'Rawhide'),
    ('fedora', 'Server netinst ISO', 'Rawhide'),
    ('fedora', 'Everything netinst ISO', 'Rawhide'),
    ('fedora', 'KDE Plasma Live ISO', 'Rawhide'),
    ('fedora', 'Xfce Live ISO', 'Rawhide'),
    ('fedora', 'LXQt Live ISO', 'Rawhide'),
    ('fedora', 'i3 Live ISO', 'Rawhide'),
    ('fedora', 'COSMIC Live ISO', 'Rawhide'),
    ('fedora', 'KDE Mobile Live ISO', 'Rawhide'),
    ('fedora', 'SoaS Live ISO', 'Rawhide'),
    ('fedora', 'Silverblue installer ISO', 'Rawhide'),
    ('fedora', 'Kinoite installer ISO', 'Rawhide'),
    ('fedora', 'COSMIC Atomic installer ISO', 'Rawhide'),
    ('ubuntu', 'Desktop ISO', '26.10'),
    ('ubuntu', 'Live server ISO', '26.10'),
    ('ubuntu', 'Preinstalled server (img.xz)', '26.10'),
    ('ubuntu', 'Cloud image', '26.10'),
    ('ubuntu', 'Minimal cloud image', '26.10'),
    ('suse', 'Online installer ISO (NET on 15.6)', 'Tumbleweed'),
    ('suse', 'GNOME Live ISO', 'Tumbleweed'),
    ('suse', 'KDE Live ISO', 'Tumbleweed'),
    ('suse', 'XFCE Live ISO', 'Tumbleweed'),
    ('suse', 'Minimal-VM Cloud (qcow2)', 'Tumbleweed'),
    ('suse', 'JeOS efi (qcow2)', 'Tumbleweed'),
    ('atomic', 'Cloud image (qcow2)', 'MicroOS'),
    ('alma', 'Boot ISO (netinstall)', 'Kitten 10'),
    ('alma', 'Minimal ISO', 'Kitten 10'),
    ('alma', 'Live GNOME ISO', 'Kitten 10'),
    ('alma', 'Live KDE ISO', 'Kitten 10'),
    ('alma', 'GenericCloud (qcow2)', 'Kitten 10'),
    ('alma', 'GenericCloud ext4 (qcow2)', 'Kitten 10'),
    ('centos', 'Boot ISO', '10'),
    ('centos', 'ec2 (raw.xz)', '10'),
    ('rocky', 'Boot ISO (netinstall)', '10.3 staging'),
    ('rocky', 'Minimal ISO', '10.3 staging'),
    ('rocky', 'GenericCloud-Base (qcow2)', '10.3 staging'),
    ('rocky', 'GenericCloud-LVM (qcow2)', '10.3 staging'),
}
# tested and does not work (the cause is in the row's footnote)
TESTED_BAD = {
    ('suse', 'Minimal-VM kvm (qcow2)', 'Leap 16.0'),
    ('suse', 'Minimal-VM kvm (qcow2)', 'Leap 15.6'),
    ('suse', 'JeOS efi (qcow2)', 'Leap 15.6'),
    ('fedora', 'Server Guest (qcow2)', '44'),
    ('fedora', 'Server Guest (qcow2)', '43'),
    ('fedora', 'IoT (raw.xz)', '44'),
    ('fedora', 'IoT (raw.xz)', '43'),
    ('alpine', 'Cloud, Tiny Cloud (qcow2)', '3.23.8'),
    ("debian", "Cloud: nocloud (qcow2)", "testing / 14 forky"),
    ("debian", "Cloud: nocloud (qcow2)", "11 bullseye (LTS)"),
    ("alpine", "Cloud, Tiny Cloud (qcow2)", "3.24.4"),
    ("fedora", "Server Guest (qcow2)", "45"),
    ("fedora", "IoT (raw.xz)", "45"),
    ("coreos", "", ""),
    ("atomic", "Installer ISO", "Leap Micro 6.2"),
    ('debian', 'Cloud: genericcloud (qcow2)', '11 bullseye (LTS)'),
    ('debian', 'Cloud: generic (qcow2)', '11 bullseye (LTS)'),
    ('fedora', 'Minimal (raw.xz)', 'Rawhide'),
    ('fedora', 'Server Guest (qcow2)', 'Rawhide'),
    ('suse', 'Minimal-VM kvm (qcow2)', 'Tumbleweed'),
    ('atomic', 'Disk image (qcow2)', 'MicroOS'),
    ("suse", "Minimal-VM kvm (qcow2)", "Leap 16.1"),
}

# ---------- Ubuntu
CD = "https://cdimage.ubuntu.com/releases"
CI = "https://cloud-images.ubuntu.com"
UBU = {"22.04 LTS": ("22.04.5", "jammy", "22.04"), "24.04 LTS": ("24.04.5", "noble", "24.04"),
       "26.04 LTS": ("26.04.1", "resolute", "26.04"), "26.10": ("26.10", "stonking", "26.10")}
ubu_cols = ["daily"] + list(UBU)[::-1]


def ub(kind):
    d = {}
    for c, (pt, code, ver) in UBU.items():
        if kind == "desktop":
            d[c] = None if ver == "22.04" else f"{CD}/{pt}/release/ubuntu-{pt}-desktop-arm64.iso"
        elif kind == "server":
            d[c] = f"{CD}/{pt}/release/ubuntu-{pt}-live-server-arm64.iso"
        elif kind == "pre":
            d[c] = None if ver == "22.04" else f"{CD}/{pt}/release/ubuntu-{pt}-preinstalled-server-arm64.img.xz"
        elif kind == "cloud":
            d[c] = f"{CI}/releases/{code}/release/ubuntu-{ver}-server-cloudimg-arm64.img"
        elif kind == "min":
            d[c] = None if ver == "22.04" else f"{CI}/minimal/releases/{code}/release/ubuntu-{ver}-minimal-cloudimg-arm64.img"
    return d


ubuntu_rows = [("Desktop ISO", ub("desktop")), ("Live server ISO", ub("server")),
               ("Preinstalled server (img.xz)", ub("pre")), ("Cloud image", ub("cloud")),
               ("Minimal cloud image", ub("min"))]

# ---------- Debian
DC = "https://cdimage.debian.org"
DEB = {"13 trixie": ("trixie", 13), "12 bookworm": ("bookworm", 12), "11 bullseye (LTS)": ("bullseye", 11)}
deb_cols = ["testing / 14 forky"] + list(DEB)


def dcloud(v):
    d = {c: f"{DC}/images/cloud/{code}/latest/debian-{n}-{v}-arm64.qcow2" for c, (code, n) in DEB.items()}
    d["testing / 14 forky"] = f"{DC}/images/cloud/forky/daily/latest/debian-14-{v}-arm64-daily.qcow2"
    return d


debian_rows = [
    ("Cloud: genericcloud (qcow2)", dcloud("genericcloud")),
    ("Cloud: generic (qcow2)", dcloud("generic")),
    ("Cloud: nocloud (qcow2)", dcloud("nocloud")),
    ("Installer: netinst ISO", {
        "13 trixie": f"{DC}/debian-cd/current/arm64/iso-cd/debian-13.7.0-arm64-netinst.iso",
        "12 bookworm": f"{DC}/cdimage/archive/12.15.0/arm64/iso-cd/debian-12.15.0-arm64-netinst.iso",
        "11 bullseye (LTS)": f"{DC}/cdimage/archive/11.11.0/arm64/iso-cd/debian-11.11.0-arm64-netinst.iso",
        "testing / 14 forky": f"{DC}/cdimage/weekly-builds/arm64/iso-cd/debian-testing-arm64-netinst.iso"}),
    ("Installer: DVD-1 ISO", {
        "13 trixie": f"{DC}/debian-cd/current/arm64/iso-dvd/debian-13.7.0-arm64-DVD-1.iso",
        "12 bookworm": f"{DC}/cdimage/archive/12.15.0/arm64/iso-dvd/debian-12.15.0-arm64-DVD-1.iso",
        "11 bullseye (LTS)": None,
        "testing / 14 forky": f"{DC}/cdimage/weekly-builds/arm64/iso-dvd/debian-testing-arm64-DVD-1.iso"}),
    ("Live GNOME ISO", {"13 trixie": None, "12 bookworm": None, "11 bullseye (LTS)": None,
                        "testing / 14 forky": f"{DC}/cdimage/weekly-live-builds/arm64/iso-hybrid/debian-live-testing-arm64-gnome.iso"}),
]

# ---------- Fedora
FB = "https://download.fedoraproject.org/pub/fedora/linux/releases"
RAW = "https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide"
# Rawhide's file names carry the compose date and there is no latest alias, so read the compose ID.
compose = subprocess.run(["curl", "-s", RAW + "/COMPOSE_ID"], capture_output=True, text=True).stdout.strip()
TAG = {"Rawhide": compose.replace("Fedora-", ""), "45": "45-1.4", "44": "44-1.7", "43": "43-1.6"}
fed_cols = list(TAG)


def fed(path, only=None, alt=None, raw=True):
    """path uses {t}; alt maps a release to its own path; raw=False leaves Rawhide out (not published there)."""
    d = {}
    for n, t in TAG.items():
        if n == "Rawhide" and not raw:
            d[n] = "-"
        elif only and n not in only:
            d[n] = None
        else:
            p = (alt or {}).get(n, path)
            base = RAW if n == "Rawhide" else f"{FB}/{n}"
            d[n] = f"{base}/" + p.format(n=n, t=t)
    return d


def live(spin, directory="Spins", raw=True):
    return fed(f"{directory}/aarch64/iso/Fedora-{spin}-Live-{{t}}.aarch64.iso", raw=raw)


INST = {"45": None, "Rawhide": None}  # the 45 and Rawhide atomic installers use the `Installer` names


def atomic(directory, new_name, old_name):
    new = f"{directory}/aarch64/iso/{new_name}"
    return fed(f"{directory}/aarch64/iso/{old_name}", alt={"45": new, "Rawhide": new})


fedora_rows = [
    ("Workstation Live ISO", fed("Workstation/aarch64/iso/Fedora-Workstation-Live-{t}.aarch64.iso")),
    ("Workstation Disk (raw.xz)", fed("Workstation/aarch64/images/Fedora-Workstation-Disk-{t}.aarch64.raw.xz")),
    ("Cloud Base (qcow2)", fed("Cloud/aarch64/images/Fedora-Cloud-Base-Generic-{t}.aarch64.qcow2")),
    ("Cloud UEFI-UKI (qcow2)", fed("Cloud/aarch64/images/Fedora-Cloud-Base-UEFI-UKI-{t}.aarch64.qcow2", only=("Rawhide", "45", "44"))),
    ("Cloud AmazonEC2 (raw.xz)", fed("Cloud/aarch64/images/Fedora-Cloud-Base-AmazonEC2-{t}.aarch64.raw.xz")),
    ("Minimal (raw.xz)", fed("Spins/aarch64/images/Fedora-Minimal-{t}.aarch64.raw.xz")),
    ("Server netinst ISO", fed("Server/aarch64/iso/Fedora-Server-netinst-aarch64-{t}.iso")),
    ("Server DVD ISO", fed("Server/aarch64/iso/Fedora-Server-dvd-aarch64-{t}.iso")),
    ("Server Guest (qcow2)", fed("Server/aarch64/images/Fedora-Server-Guest-Generic-{t}.aarch64.qcow2")),
    ("Everything netinst ISO", fed("Everything/aarch64/iso/Fedora-Everything-netinst-aarch64-{t}.iso")),
    ("KDE Plasma Live ISO", fed("KDE/aarch64/iso/Fedora-KDE-Desktop-Live-{t}.aarch64.iso")),
    ("KDE Plasma Disk (raw.xz)", fed("KDE/aarch64/images/Fedora-KDE-Desktop-Disk-{t}.aarch64.raw.xz")),
    ("Xfce Live ISO", live("Xfce")), ("LXQt Live ISO", live("LXQt")), ("i3 Live ISO", live("i3")),
    ("COSMIC Live ISO", live("COSMIC")), ("KDE Mobile Live ISO", live("KDE-Mobile")),
    ("MiracleWM Live ISO", live("MiracleWM", raw=False)), ("SoaS Live ISO", live("SoaS")),
    ("Silverblue installer ISO", atomic("Silverblue", "Fedora-Silverblue-Installer-{t}.aarch64.iso", "Fedora-Silverblue-ostree-aarch64-{t}.iso")),
    ("Kinoite installer ISO", atomic("Kinoite", "Fedora-Kinoite-Installer-{t}.aarch64.iso", "Fedora-Kinoite-ostree-aarch64-{t}.iso")),
    ("COSMIC Atomic installer ISO", atomic("COSMIC-Atomic", "Fedora-CosmicAtomic-Installer-{t}.aarch64.iso", "Fedora-COSMIC-Atomic-ostree-aarch64-{t}.iso")),
    ("Python Classroom Live ISO", fed("Labs/aarch64/iso/Fedora-Python-Classroom-Live-{t}.aarch64.iso", raw=False)),
    ("Scientific KDE Live ISO", fed("Labs/aarch64/iso/Fedora-Scientific_KDE-Live-{t}.aarch64.iso", only=("45", "44"), raw=False)),
]
IOT = "https://dl.fedoraproject.org/pub/alt/iot"
fedora_rows.append(("IoT (raw.xz)", {
    "Rawhide": "-",
    "45": f"{IOT}/45/IoT/aarch64/images/Fedora-IoT-raw-45-20261031.0.aarch64.raw.xz",
    "44": f"{IOT}/44/IoT/aarch64/images/Fedora-IoT-raw-44-20260427.0.aarch64.raw.xz",
    "43": f"{IOT}/43/IoT/aarch64/images/Fedora-IoT-raw-43-20251024.0.aarch64.raw.xz"}))
COREOS = "https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/44.20261023.3.1/aarch64"
coreos_url = f"{COREOS}/fedora-coreos-44.20261023.3.1-applehv.aarch64.raw.gz"

# ---------- Alpine
AL = "https://dl-cdn.alpinelinux.org/alpine"
alp_cols = ["edge", "3.24.4", "3.23.8"]


def alp(fmt24, fmt23):
    return {"3.24.4": f"{AL}/v3.24/releases/" + fmt24, "3.23.8": f"{AL}/v3.23/releases/" + fmt23}


alpine_rows = [
    ("Standard ISO", alp("aarch64/alpine-standard-3.24.4-aarch64.iso", "aarch64/alpine-standard-3.23.8-aarch64.iso")),
    ("Virt ISO", alp("aarch64/alpine-virt-3.24.4-aarch64.iso", "aarch64/alpine-virt-3.23.8-aarch64.iso")),
    ("Cloud, cloud-init (qcow2)", alp("cloud/alpine-3.24.4-aarch64-cloudinit-r0.qcow2", "cloud/alpine-3.23.8-aarch64-uefi-cloudinit-r0.qcow2")),
    ("Cloud, Tiny Cloud (qcow2)", alp("cloud/alpine-3.24.4-aarch64-tiny-r0.qcow2", "cloud/alpine-3.23.8-aarch64-uefi-tiny-r0.qcow2")),
]

# ---------- Pop!_OS
POP = "https://iso.pop-os.org/24.04/arm64"
pop_rows = [("24.04 LTS", "ARM generic ISO", f"{POP}/generic/3/pop-os_24.04_arm64_generic_3.iso"),
            ("24.04 LTS", "ARM NVIDIA ISO", f"{POP}/nvidia/3/pop-os_24.04_arm64_nvidia_3.iso")]

exec(open(os.path.join(HERE, "distros_more.py")).read(), globals())
REFS.update({
    ("rocky", "Boot ISO (netinstall)"): "[^el-installer]", ("rocky", "Minimal ISO"): "[^el-installer]",
    ("rocky", "DVD ISO"): "[^el-installer]",
    ("rocky", "GenericCloud-Base (qcow2)"): "[^el-cloud]", ("rocky", "GenericCloud-LVM (qcow2)"): "[^el-cloud]",
    ("alma", "Boot ISO (netinstall)"): "[^el-installer]", ("alma", "Minimal ISO"): "[^el-installer]",
    ("alma", "DVD ISO"): "[^el-installer]", ("alma", "Live GNOME ISO"): "[^alma-live]",
    ("alma", "GenericCloud (qcow2)"): "[^el-cloud]", ("alma", "GenericCloud ext4 (qcow2)"): "[^el-cloud]",
    ("centos", "Boot ISO"): "[^el-installer]", ("centos", "DVD ISO"): "[^el-installer]",
    ("centos", "GenericCloud (qcow2)"): "[^el-cloud]", ("centos", "ec2 (raw.xz)"): "[^centos-ec2]",
    ("oracle", "DVD ISO"): "[^oracle]", ("oracle", "kvm-cloud (qcow2)"): "[^oracle]",
    ("suse", "Minimal-VM Cloud (qcow2)"): "[^suse-cloud]", ("suse", "Offline installer ISO (DVD on 15.6)"): "[^suse-installer]",
    ("suse", "Minimal-VM kvm (qcow2)"): "[^suse-kvm]",
    ("atomic", "Cloud image (qcow2)"): "[^suse-cloud]", ("atomic", "Disk image (qcow2)"): "[^suse-atomic]",
})
# ---------- macOS, from ipsw.me
api = json.loads(subprocess.run(["curl", "-s", "https://api.ipsw.me/v4/device/VirtualMac2,1?type=ipsw"],
                                capture_output=True, text=True).stdout)
by_version = {f["version"]: f for f in api["firmwares"]}
MAC = ["27.2", "27.0", "26.6.2", "26.0", "15.6.1", "14.6.1", "13.6", "12.6"]
NAMES = {"27": "macOS 27", "26": "macOS 26", "15": "Sequoia 15", "14": "Sonoma 14", "13": "Ventura 13", "12": "Monterey 12"}

# ---------- verify everything in parallel first
urls = set()
for rows in (ubuntu_rows, debian_rows, fedora_rows, alpine_rows, rocky_rows, alma_rows, centos_rows, oracle_rows,
             suse_rows, atomic_rows):
    for _, cells in rows:
        urls.update(u for u in cells.values() if u not in (None, "-"))
urls.update([coreos_url, AL2023] + [r[2] for r in pop_rows] + [by_version[v]["url"] for v in MAC if v in by_version])
urls.update(r[3] for r in specialty + bsd)
with ThreadPoolExecutor(12) as ex:
    list(ex.map(head, sorted(urls)))

# ---------- assemble
ubuntu = grid("ubuntu", ubu_cols, ubuntu_rows, TESTED)
debian = grid("debian", deb_cols, debian_rows, TESTED)
fedora = grid("fedora", fed_cols, fedora_rows, TESTED)
alpine = grid("alpine", alp_cols, alpine_rows, TESTED)

pop = pivot([("Pop!_OS", rel, var, u) for rel, var, u in pop_rows])

MAC_GROUP = {"27.2": EVERYDAY, "27.0": EVERYDAY, "26.6.2": EVERYDAY, "26.0": BEHIND, "15.6.1": BEHIND,
             "14.6.1": BEHIND, "13.6": BEHIND, "12.6": BEHIND}
mac = ["| macOS | Build | Status | Image |", "|---|---|---|---|",
       f"| {EDGE} Beta or seed[^macos-beta] | | {NONE} | none found |"]
for v in MAC:
    f = by_version.get(v)
    if not f:
        FAILED.append(("macos", v, "", "missing from ipsw.me", 0))
        continue
    st, size = head(f["url"])
    if st != 200:
        FAILED.append(("macos", v, "", f["url"], st))
    name = NAMES[v.split(".")[0]]
    mark = OK if v == "27.2" else UNTESTED
    mac.append(f"| {MAC_GROUP.get(v, '')} {name} ({v}) | {f['buildid']} | {mark} | [{size / 1e9:.1f} GB]({f['url']}) |")

coreos_status, coreos_size = head(coreos_url)
if coreos_status != 200:
    FAILED.append(("coreos", "", "", coreos_url, coreos_status))

rocky_t = grid("rocky", rocky_cols, rocky_rows, TESTED)
alma_t = grid("alma", alma_cols, alma_rows, TESTED)
centos_t = grid("centos", cs_cols, centos_rows, TESTED)
oracle_t = grid("oracle", ol_cols, oracle_rows, TESTED)
suse_t = grid("suse", suse_cols, suse_rows, TESTED)
atomic_t = grid("atomic", atomic_cols, atomic_rows, TESTED)
al_s, al_size = head(AL2023)
if al_s != 200:
    FAILED.append(("amazon", "", "", AL2023, al_s))
amazon_t = pivot([("Amazon Linux 2023", "2023", "KVM arm64 (qcow2)[^amazon]", AL2023)])

# ---------- popularity index: DistroWatch 12-month page-hit ranking read on RANK_DATE: (rank, name, hits/day, tables, flat names)
RANKED = [
    (1, "CachyOS", 3219, None), (2, "Linux Mint", 1967, None), (3, "MX Linux", 1749, None),
    (4, "Debian", 1258, (["debian"], [])), (5, "Pop!_OS", 1248, (["pop"], [])), (6, "Zorin OS", 1144, None),
    (7, "Fedora", 1123, (["fedora"], [])), (8, "EndeavourOS", 981, None),
    (9, "Ubuntu", 951, (["ubuntu"], [])), (10, "Manjaro", 893, None), (11, "Bazzite", 830, None),
    (14, "Arch Linux ARM", 633, None), (15, "openSUSE", 631, (["suse", "atomic"], [])), (17, "Nobara", 552, None),
    (20, "NixOS", 500, ([], ["NixOS"])), (22, "elementary OS", 450, None), (24, "Void Linux", 433, ([], ["Void Linux"])),
    (30, "Alpine", 341, (["alpine"], [])), (33, "Kali Linux", 324, ([], ["Kali Linux"])), (42, "Tails", 293, None),
    (45, "Solus", 278, None), (47, "Parrot OS", 269, ([], ["Parrot OS"])), (51, "AlmaLinux", 252, (["alma"], [])),
    (52, "CentOS Stream", 250, (["centos"], [])), (55, "Gentoo", 235, ([], ["Gentoo"])), (62, "Slackware", 201, None),
    (67, "Rocky Linux", 192, (["rocky"], [])), (76, "Deepin", 184, ([], ["Deepin"])), (98, "Qubes OS", 153, None),
    (177, "Oracle Linux", 79, (["oracle"], [])), (None, "Amazon Linux 2023", None, (["amazon"], [])),
]


DW = {"CachyOS": "cachyos", "Linux Mint": "mint", "MX Linux": "mx", "Debian": "debian", "Pop!_OS": "popos",
      "Zorin OS": "zorin", "Fedora": "fedora", "EndeavourOS": "endeavour", "Ubuntu": "ubuntu", "Manjaro": "manjaro",
      "Bazzite": "bazzite", "Arch Linux ARM": "arch", "openSUSE": "opensuse", "Nobara": "nobara", "NixOS": "nixos",
      "elementary OS": "elementary", "Void Linux": "void", "Alpine": "alpine", "Kali Linux": "kali", "Tails": "tails",
      "Solus": "solus", "Parrot OS": "parrot", "AlmaLinux": "alma", "CentOS Stream": "centos", "Gentoo": "gentoo",
      "Slackware": "slackware", "Rocky Linux": "rocky", "Deepin": "deepin", "Qubes OS": "qubes", "Oracle Linux": "oracle"}


def slug(name):
    return re.sub(r"[^a-z0-9_ -]", "", name.lower()).replace(" ", "-")


def best(tables, flats):
    if any(t[0] in tables for t in TESTED) or any(k[0] in flats for k in TESTED_FLAT):
        return OK
    return UNTESTED


idx = ["| Rank[^distrowatch] | Distribution | Hits per day | aarch64 |", "|---|---|---|---|"]
for rank, name, hits, spec in RANKED:
    mark = NONE if spec is None else best(*spec)
    rank_cell = f"[{rank}](https://distrowatch.com/{DW[name]})" if rank else "—"
    idx.append(f"| {rank_cell} | [{name}](#{slug(name)}) | {hits if hits else 'not ranked'} | {mark} |")
INDEX = "\n".join(idx)


TEMPLATE = open(TEMPLATE_PATH).read()
TEMPLATE = re.sub(r"@FLAT:(.+?)@", lambda mo: pivot([r for r in specialty + bsd if r[0] == mo.group(1)]), TEMPLATE)
doc = (TEMPLATE.replace("@INDEX@", INDEX).replace("@ELCLOUD@", EL_CLOUD).replace("@SUSECLOUD@", SUSE_CLOUD).replace("@KITTEN@", KITTEN).replace("@ROCKY@", rocky_t).replace("@ALMA@", alma_t).replace("@CENTOS@", centos_t)
       .replace("@ORACLE@", oracle_t).replace("@AMAZON@", amazon_t).replace("@SUSE@", suse_t)
       .replace("@ATOMIC@", atomic_t).replace("@SPECIALTY@", flat(specialty))
       .replace("@COMPOSE@", compose.replace("Fedora-", "")).replace("@RANKDATE@", RANK_DATE).replace("@DATE@", DATE).replace("@UBUNTU@", ubuntu).replace("@DEBIAN@", debian)
       .replace("@FEDORA@", fedora).replace("@ALPINE@", alpine).replace("@POP@", pop)
       .replace("@MAC@", "\n".join(mac))
       .replace("@COREOS@", f"{BAD if ('coreos', '', '') in TESTED_BAD else UNTESTED} [{coreos_size / 1e9:.2f} GB]({coreos_url})"))
open(OUT, "w").write(doc)
print("urls checked:", len(CACHE), " failed:", len(FAILED))
for f in FAILED:
    print("FAILED", f)
