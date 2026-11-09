"""Checks the core's layering: a directory under core/ may use only the directories below it.
Usage: layers.py CORE_DIR. Names are matched by identifier, after comments and string literals are removed."""
import collections, glob, os, re, sys

core = sys.argv[1]
# Lowest first; directories of one rank do not use each other.
ranks = [["system"], ["images", "display", "guestlink"], ["vm"], ["recipes", "tweaks"], ["owner"], ["verbs"]]
rank = {d: i for i, ds in enumerate(ranks) for d in ds}


def layer(path):
    return os.path.relpath(path, core).split(os.sep)[0] if os.sep in os.path.relpath(path, core) else "(root)"


def strip(source):
    source = re.sub(r'"""(?:.|\n)*?"""', '""', source)
    source = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', source)
    return re.sub(r"//.*", "", source)


files = {f: strip(open(f).read()) for f in glob.glob(os.path.join(core, "**", "*.swift"), recursive=True)}
declared = collections.defaultdict(set)
for f, text in files.items():
    for m in re.finditer(r"^(?:@\w+ )*(?:public |package |final )*(?:enum|struct|class|protocol|typealias|func|let|var) (\w+)", text, re.M):
        declared[m.group(1)].add(layer(f))

problems = set()
for f, text in files.items():
    here = layer(f)
    if here == "(root)":
        continue
    words = set(re.findall(r"\b\w+\b", text))
    for name, layers in declared.items():
        if name in words and len(layers) == 1:
            there = next(iter(layers))
            if there not in (here, "(root)") and rank[there] >= rank[here]:
                problems.add(f"{here} uses {name} from {there}")

for p in sorted(problems):
    print("FAIL " + p)
print(f"{len(problems)} layering problem(s)")
sys.exit(1 if problems else 0)
