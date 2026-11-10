"""Checks the Markdown docs: relative links and #anchors resolve, and no doc or script uses the removed `--vm`.
Usage: docs.py ROOT. Skips CHANGELOG.md's history, drafts, the distros template, and fenced code."""
import glob, os, re, sys

root = sys.argv[1]
skip = {"CHANGELOG.md", "tools/distros.template.md"}  # the template's links are relative to docs/
files = [f for f in glob.glob(os.path.join(root, "**", "*.md"), recursive=True)
         if not re.search(r"(^|/)(\.|_|,)|\.draft\.md$|\.zig-cache|zig-out", os.path.relpath(f, root))
         and os.path.relpath(f, root) not in skip]


def prose(path):
    return re.sub(r"^```.*?^```", "", open(path).read(), flags=re.S | re.M)


def anchors(path):
    out = set()
    for h in re.findall(r"^#+ (.*)$", prose(path), re.M):
        h = re.sub(r"[`*]|\[([^\]]*)\]\([^)]*\)", r"\1", h)
        out.add(re.sub(r"[^\w -]", "", h.lower()).strip().replace(" ", "-"))
    return out


bad = []
for f in files:
    rel = os.path.relpath(f, root)
    for t in re.findall(r"\]\(([^)\s]+)\)", prose(f)):
        if re.match(r"[a-z]+:", t):
            continue
        path, _, frag = t.partition("#")
        target = os.path.normpath(os.path.join(os.path.dirname(f), path)) if path else f
        if not os.path.exists(target):
            bad.append(f"{rel}: missing {t}")
        elif frag and target.endswith(".md") and frag not in anchors(target):
            bad.append(f"{rel}: no anchor {t}")
    if "--vm" in open(f).read():
        bad.append(f"{rel}: mentions --vm")
for f in glob.glob(os.path.join(root, "tools", "*")) + glob.glob(os.path.join(root, "tests", "*.py")):
    if os.path.isfile(f) and os.path.abspath(f) != os.path.abspath(__file__) and "--vm" in open(f, errors="ignore").read().replace('"--vm"', ""):
        bad.append(f"{os.path.relpath(f, root)}: mentions --vm")
print("\n".join(bad))
print(f"{len(bad)} failure(s) in {len(files)} docs")
sys.exit(1 if bad else 0)
