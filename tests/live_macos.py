"""Checks of `terrarium mcp` against a live macOS guest. Usage: live_macos.py BINARY GUEST
GUEST is an installed macOS guest (`NAME.guest`, from `--install macos --user terra --accept-license` and `commit`)."""
import base64, json, os, shutil, sys, tempfile, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from client import Client, Checks

binary, guest = sys.argv[1], sys.argv[2]
check = Checks()


def text(r):
    return "".join(b.get("text", "") for b in r["result"]["content"] if b["type"] == "text")


def out(r):
    return r["result"]["structuredContent"]["stdout"]


c = Client(binary)
r, _ = c.call("start", {"image": guest}, timeout=120)
vm = r["result"]["structuredContent"]["id"]
check("start of a guest returns the VM id", r["result"]["isError"] is False and len(vm) == 8, r)

for _ in range(60):
    r, _ = c.call("exec", {"command": "/usr/bin/whoami"})
    if not r["result"]["isError"]:
        break
    time.sleep(5)
check("the helper answers", not r["result"]["isError"], r)
check("the helper runs as terra", out(r) == "terra\n", r)

r, _ = c.call("exec", {"command": "/usr/bin/sudo", "args": ["-n", "/usr/bin/id", "-un"]})
check("terra has passwordless sudo", out(r) == "root\n", r)
r, _ = c.call("tweak", {"name": "macos/no-sleep"})
check("the no-sleep tweak succeeds", r["result"]["isError"] is False, r)
r, _ = c.call("exec", {"command": "/usr/bin/pmset", "args": ["-g"]})
check("sleep is off", " sleep                0" in out(r) and " displaysleep         0" in out(r), out(r))

for name, domain, key, want in [
        ("macos/no-screensaver", "com.apple.screensaver", "askForPassword", "0"),
        ("macos/quiet-setup", "com.apple.SetupAssistant", "DidSeeSiriSetup", "1")]:
    for again in ("", " again"):
        r, _ = c.call("tweak", {"name": name})
        check("the %s tweak succeeds%s" % (name, again), r["result"]["isError"] is False, r)
    r, _ = c.call("exec", {"command": "/usr/bin/defaults", "args": ["read", domain, key]})
    check("%s set %s" % (name, key), out(r).strip() == want, r)
r, _ = c.call("tweak", {"name": "linux/no-blank"})
check("a tweak for another OS is refused", r["result"]["isError"] is True, r)

sample = "line one\nhéllo\ttab ☃ \U0001F331\n"
r, _ = c.call("clipboard", {"action": "set", "text": sample})
check("clipboard set goes through the helper (nothing typed)", r["result"]["isError"] is False and text(r) == "ok", r)
r, _ = c.call("clipboard", {"action": "get"})
check("clipboard get returns the text exactly, multi-line and non-ASCII", r["result"]["isError"] is False and text(r) == sample, text(r))
# `exec` has no LANG, so pbpaste would print MacRoman; the helper's own clipboard calls set a UTF-8 locale.
r, _ = c.call("exec", {"command": "/usr/bin/env", "args": ["LANG=en_US.UTF-8", "/usr/bin/pbpaste"]})
check("the guest's own pbpaste sees it", out(r) == sample, out(r))

block = c.call("shot")[0]["result"]["content"][0]
check("shot: an image block with a PNG",
      block["type"] == "image" and base64.b64decode(block["data"])[:8] == b"\x89PNG\r\n\x1a\n")
r, _ = c.call("click", {"at": "100,100"})
check("click answers ok", r["result"]["isError"] is False and text(r) == "ok", r)

r, _ = c.call("stop", {"id": vm})
check("stop answers", r["result"]["isError"] is False, r)
check("ps no longer lists it", vm not in text(c.call("ps")[0]))
manifest = json.load(open(os.path.join(guest, "manifest.json")))
work = tempfile.mkdtemp(prefix="terrarium-test-")
marker = "/Users/terra/marker"


def boot(**arguments):
    r, _ = c.call("start", {"image": guest, **arguments}, timeout=180)
    if r["result"]["isError"]:
        return None, r
    v = r["result"]["structuredContent"]["id"]
    for _ in range(60):
        if not c.call("exec", {"vm": v, "command": "/usr/bin/true"})[0]["result"]["isError"]:
            break
        time.sleep(5)
    return v, r


def read(v):
    return c.call("exec", {"vm": v, "command": "/bin/sh", "args": ["-c", "cat %s 2>&1 || true" % marker]})[0]["result"]["structuredContent"]["stdout"]


layer = os.path.join(guest, "overlay.asif")
size = os.path.getsize(layer)
vm, r = boot(overlay=work + "/new.overlay")
check("start with an overlay that does not exist starts a new layer", vm is not None, r)
r, _ = c.call("exec", {"vm": vm, "command": "/bin/sh", "args": ["-c", "echo over-guest > %s; sync" % marker]})
check("the guest writes to it", not r["result"]["isError"], r)
r, _ = c.call("commit", {"id": vm, "path": work + "/var"})
saved = text(r)
check("commit saves PATH-<guestid>.overlay", r["result"]["isError"] is False and saved == "%s/var-%s.overlay" % (work, manifest["id"]) and os.path.exists(saved), r)
c.call("stop", {"id": vm})

vm, r = boot(overlay=saved)
check("an overlay saved over the guest boots over it", vm is not None, r)
check("and holds what was written", vm is not None and read(vm) == "over-guest\n", vm and read(vm))
if vm:
    c.call("stop", {"id": vm})

vm, r = boot()
check("the guest itself does not hold it", vm is not None and "over-guest" not in read(vm), r)
if vm:
    c.call("stop", {"id": vm})
check("the guest's layer is unchanged", os.path.getsize(layer) == size)

vm, r = boot(tweak=["macos/no-sleep"])
check("start --tweak runs the tweak before returning", vm is not None, r)
if vm:
    r, _ = c.call("exec", {"vm": vm, "command": "/usr/bin/pmset", "args": ["-g"]})
    check("and it took effect", " sleep                0" in out(r), out(r))
    c.call("stop", {"id": vm})

wrong = work + "/x-0123456789abcdef.overlay"
if os.path.isdir(saved):
    shutil.copytree(saved, wrong)
else:
    os.link(saved, wrong)
r, _ = c.call("start", {"image": guest, "overlay": wrong})
check("an overlay named for another guest is refused", r["result"]["isError"] is True and "another guest" in text(r), r)
check("--install with a guest is refused", c.call("start", {"image": guest, "install": "macos"})[0]["result"]["isError"] is True)
shutil.rmtree(work, ignore_errors=True)

check("stdout carried only JSON lines", not c.bad, c.bad)
check("exits when stdin closes", c.close() == 0)
check.finish()
