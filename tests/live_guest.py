"""Checks of `terrarium mcp` against a live Linux guest: overlays over an installed guest. Usage: live_guest.py BINARY GUEST
GUEST is an installed Linux guest (`NAME.guest`, from `--install alpine` and `commit`) saved with an `id`."""
import json, os, sys, tempfile, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from client import Client, Checks

binary, guest = sys.argv[1], sys.argv[2]
check = Checks()
work = tempfile.mkdtemp(prefix="terrarium-test-")
c = Client(binary)


def text(r):
    return "".join(b.get("text", "") for b in r["result"]["content"] if b["type"] == "text")


def boot(**arguments):
    r, _ = c.call("start", {"image": guest, "memory": 1024, "cpus": 2, **arguments}, timeout=120)
    if r["result"]["isError"]:
        return None, r
    vm = r["result"]["structuredContent"]["id"]
    for _ in range(40):
        if not c.call("exec", {"vm": vm, "command": "true"})[0]["result"]["isError"]:
            return vm, r
        time.sleep(3)
    return vm, r


def read(vm):
    r, _ = c.call("exec", {"vm": vm, "command": "sh", "args": ["-c", "cat /root/marker 2>&1 || true"]})
    return r["result"]["structuredContent"]["stdout"]


manifest = json.load(open(os.path.join(guest, "manifest.json")))
check("the guest has an id", len(manifest.get("id", "")) == 16, manifest)
size = os.path.getsize(os.path.join(guest, "overlay.asif"))

vm, r = boot(overlay=work + "/new.overlay")
check("start with an overlay path that does not exist starts a new layer", vm is not None, r)
r, _ = c.call("exec", {"vm": vm, "command": "sh", "args": ["-c", "echo over-guest > /root/marker; sync"]})
check("the guest writes to it", not r["result"]["isError"], r)
r, _ = c.call("commit", {"id": vm, "path": work + "/var"})
saved = text(r)
check("commit saves PATH-<guestid>.overlay", r["result"]["isError"] is False and saved == "%s/var-%s.overlay" % (work, manifest["id"]) and os.path.isfile(saved), r)
check("and it is smaller than the guest's layer", 0 < os.path.getsize(saved) < size, (os.path.getsize(saved), size))
c.call("stop", {"id": vm})

vm, r = boot(overlay=saved)
check("an overlay saved over the guest boots over it", vm is not None, r)
check("and holds what was written", read(vm) == "over-guest\n", read(vm))
c.call("stop", {"id": vm})

vm, r = boot()
check("the guest itself does not hold it", vm is not None and "over-guest" not in read(vm), r)
c.call("stop", {"id": vm})
check("the guest's layer is unchanged", os.path.getsize(os.path.join(guest, "overlay.asif")) == size)

vm, r = boot(tweak=["linux/alpine-repositories"])
check("start --tweak runs the tweak before returning", vm is not None, r)


def run(command):
    r, _ = c.call("exec", {"vm": vm, "command": "sh", "args": ["-c", command]})
    return r["result"]["structuredContent"]["stdout"]


for name in ("linux/alpine-repositories", "linux/no-blank"):
    for again in ("", " again"):
        r, _ = c.call("tweak", {"vm": vm, "name": name})
        check("the %s tweak succeeds%s" % (name, again), r["result"]["isError"] is False, r)
repositories = run("cat /etc/apk/repositories").split()
check("alpine-repositories leaves main and community of one mirror",
      len(repositories) == 2 and repositories[0].endswith("/main") and repositories[1].endswith("/community")
      and repositories[0][:-5] == repositories[1][:-10], repositories)
check("no-blank writes its boot hook", run("test -x /etc/local.d/no-blank.start && echo yes") == "yes\n")
check("a tweak for another OS is refused", c.call("tweak", {"vm": vm, "name": "windows/no-sleep"})[0]["result"]["isError"] is True)
c.call("stop", {"id": vm})

wrong = work + "/x-0123456789abcdef.overlay"
os.link(saved, wrong)
r, _ = c.call("start", {"image": guest, "overlay": wrong})
check("an overlay named for another guest is refused", r["result"]["isError"] is True and "another guest" in text(r), r)
check("--install with a guest is refused", c.call("start", {"image": guest, "install": "alpine"})[0]["result"]["isError"] is True)

for f in os.listdir(work):
    os.remove(os.path.join(work, f))
os.rmdir(work)
c.close()
check.finish()
