"""Checks that every tweak script is in Tweaks.catalog and build.zig's assets under one section, and has a row in
docs/tweaks.md whose description and timeout are the script header's. Usage: tweaks.py ROOT"""
import glob, os, re, sys

root = sys.argv[1]
catalog = dict(((o, n), s) for o, n, s in re.findall(r'Tweak\(os: \.(\w+), name: "([^"]+)", section: "([^"]+)"\)', open(os.path.join(root, "core/tweaks/Tweaks.swift")).read()))
assets = dict((p, s) for s, p in re.findall(r'\.section = "([^"]+)", \.path = "(core/tweaks/[^"]+)"', open(os.path.join(root, "build.zig")).read()))
rows = dict((p, (d, int(t))) for p, d, t in re.findall(r"^\| \[`[^`]+`\]\(\.\./(core/tweaks/[^)]+)\) \| (.*) \| (\d+) s \|$", open(os.path.join(root, "docs/tweaks.md")).read(), re.M))


def header(path):
    """The description and timeout, read as Tweaks.header reads them."""
    lines = [line.strip() for line in open(path).read().split("\n")]
    if lines and lines[0].startswith("#!"):
        lines = lines[1:]
    comments = []
    for line in lines:
        if not line.startswith("#"):
            break
        comments.append(line[1:].lstrip(" "))
    timeout = 10
    for line in comments[1:]:
        m = re.match(r"timeout:\s*(\d+)\s*$", line)
        if m:
            timeout = int(m.group(1))
    return (comments[0] if comments else ""), timeout


bad = []
scripts = sorted(os.path.relpath(f, root) for f in glob.glob(os.path.join(root, "core/tweaks/*/*.*")))
for path in scripts:
    os_name, file = path.split("/")[2:]
    name = os.path.splitext(file)[0]
    section = catalog.get((os_name, name))
    if section is None:
        bad.append(f"{path}: not in Tweaks.catalog")
    elif assets.get(path) != section:
        bad.append(f"{path}: build.zig embeds it as {assets.get(path)}, but the catalog reads {section}")
    description, timeout = header(os.path.join(root, path))
    if path not in rows:
        bad.append(f"{path}: no row in docs/tweaks.md")
        continue
    row, row_timeout = rows[path]
    if description != row[:1].upper() + row[1:] + ".":
        bad.append(f"{path}: its header says {description!r}, but docs/tweaks.md says {row!r}")
    if timeout != row_timeout:
        bad.append(f"{path}: its timeout is {timeout} s, but docs/tweaks.md says {row_timeout} s")
for (os_name, name), section in catalog.items():
    if not any(p.startswith(f"core/tweaks/{os_name}/{name}.") for p in scripts):
        bad.append(f"Tweaks.catalog: {os_name}/{name} has no script")
for path in set(assets) | set(rows):
    if path not in scripts:
        bad.append(f"{path}: named, but no such script")
print("\n".join(bad))
print(f"{len(bad)} failure(s) in {len(scripts)} tweaks")
sys.exit(1 if bad else 0)
