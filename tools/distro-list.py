#!/usr/bin/python3 -I
"""Prints the ⬜ (untested) cells of docs/distros.md as a batch list for distro-batch.sh: lines of `MODE LABEL URL`.
Usage: tools/distro-list.py [--groups 🟧🟩🟫] [--max-gb 5] [--skip REGEX] [DOC]
  --groups   which columns to take: 🟩 everyday, 🟧 bleeding edge, 🟫 falling behind (default: all; flat tables have no group)
  --max-gb   skip bigger images (default 5; the DVDs, IPSWs, and desktop disks are in the way of a small disk)
  --skip     extra pattern (case-insensitive, on the URL) to leave out; the default skips images known not to work or to need a recipe
Modes: .iso is `shot`; a name with `nocloud` is `nocloud`; any other disk image is `cloud`. Regenerate docs/distros.md first
(`python3 tools/distros.py`), since dated URLs go stale within days."""
import re, sys, os

DEFAULT_SKIP = r"dvd|kvm|tiny|jeos|-efi\.|disk-|server-guest|fedora-minimal|iot|ubuntu-core|leap-micro|microos|coreos|\.utm|windows|ipsw|freebsd|netbsd|openbsd"
args = sys.argv[1:]
opt = {"--groups": "🟧🟩🟫", "--max-gb": "5", "--skip": DEFAULT_SKIP}
doc = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "distros.md")
while args:
    a = args.pop(0)
    if a in opt: opt[a] = args.pop(0)
    else: doc = a
groups, max_gb, skip = opt["--groups"], float(opt["--max-gb"]), re.compile(opt["--skip"], re.I)
cell = re.compile(r"⬜ \[([\d.]+) GB\]\((\S+?)\)")
out, seen = [], set()
lines = open(doc).read().split("\n")
group_cols = None
for l in lines:
    if not l.startswith("|"): group_cols = None; continue
    cells = [c.strip() for c in l.strip().strip("|").split("|")]
    if any(g in l for g in "🟧🟩🟫") and l.startswith("| Variant"):
        group_cols = [k for k, h in enumerate(cells) if any(g in h and g in groups for g in "🟧🟩🟫")]
        continue
    if l.startswith("|---") or l.startswith("| Release") or l.startswith("| Distribution"): 
        if l.startswith("| Release") or l.startswith("| Distribution"): group_cols = None
        continue
    for k, c in enumerate(cells):
        if group_cols is not None and k not in group_cols: continue
        m = cell.search(c)
        if not m: continue
        size, url = float(m.group(1)), m.group(2)
        if size > max_gb or skip.search(url) or url in seen: continue
        seen.add(url)
        base = url.rsplit("/", 1)[1]
        label = re.sub(r"[^A-Za-z0-9.-]", "_", re.sub(r"\.(qcow2|iso|img|raw\.xz|img\.xz|qcow2\.xz|img\.gz|raw\.gz)$", "", base))
        mode = "shot" if url.endswith(".iso") else "nocloud" if "nocloud" in url.lower() else "cloud"
        out.append(f"{mode} {label} {url}")
print("\n".join(out))
print(f"{len(out)} images", file=sys.stderr)
