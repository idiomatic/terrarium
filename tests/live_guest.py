"""Checks of `terrarium mcp` against a live Linux guest: layers. Usage: live_guest.py BINARY LAYER
LAYER is a Linux layer with the helper in it (`NAME.layer`, e.g. a provisioned image saved with `commit`)."""
import json, os, shutil, subprocess, sys, tempfile, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from client import Client, Checks

binary, layer = sys.argv[1], sys.argv[2]
check = Checks()
work = tempfile.mkdtemp(prefix="terrarium-test-")
c = Client(binary)


def text(r):
    return "".join(b.get("text", "") for b in r["result"]["content"] if b["type"] == "text")


def boot(target=layer, **arguments):
    if not any(name in arguments for name in ("save", "clone", "continue")):
        arguments["ephemeral"] = True
    r, _ = c.call("start", {"image": target, "memory": 1024, "cpus": 2, **arguments}, timeout=120)
    if r["result"]["isError"]:
        return None, r
    vm = r["result"]["structuredContent"]["id"]
    for _ in range(40):
        if not c.call("exec", {"vm": vm, "command": "true"})[0]["result"]["isError"]:
            return vm, r
        time.sleep(3)
    return vm, r


def sh(vm, script):
    r, _ = c.call("exec", {"vm": vm, "command": "sh", "args": ["-c", script]})
    return r["result"]["structuredContent"]["stdout"]


def manifest(bundle):
    return json.load(open(os.path.join(bundle, "manifest.json")))


parent = manifest(layer)
check("the layer has an id and a chain", len(parent.get("id", "")) == 16 and isinstance(parent.get("chain"), list), parent)

# Extend: a child of the layer (saved by a manual commit here).
vm, r = boot()
check("a layer boots", vm is not None, r)
sh(vm, "echo child > /root/marker; sync")
r, _ = c.call("commit", {"vm": vm, "layer": work + "/child"})
child = text(r)
check("commit saves a child, NAME.layer", r["result"]["isError"] is False and child == work + "/child.layer" and os.path.isdir(child), r)
check("its chain is the parent's and the parent", manifest(child)["chain"] == parent["chain"] + [parent["id"]], manifest(child))
check("commit refuses an existing layer", c.call("commit", {"vm": vm, "layer": work + "/child"})[0]["result"]["isError"] is True)
c.call("stop", {"vm": vm})

vm, r = boot(child)
check("the child boots and holds what was written", vm is not None and sh(vm, "cat /root/marker 2>&1 || true") == "child\n", r)
c.call("stop", {"vm": vm})
vm, r = boot()
check("the parent does not", vm is not None and "child" not in sh(vm, "cat /root/marker 2>&1 || true"), r)

# Clone: a sibling that keeps the layer's changes, saved when the VM stops.
c.call("stop", {"vm": vm})
vm, r = boot(clone=work + "/sibling")
check("a layer boots with --clone", vm is not None, r)
check("a second VM aiming at the same layer is refused", c.call("start", {"image": layer, "clone": work + "/sibling"})[0]["result"]["isError"] is True)
sh(vm, "echo sibling > /root/sibling; sync")
c.call("stop", {"vm": vm})
sibling = work + "/sibling.layer"
check("stop saved a sibling with the same chain", os.path.isdir(sibling) and manifest(sibling)["chain"] == parent["chain"], os.listdir(work))
vm, r = boot(sibling)
check("and it holds what was written", vm is not None and sh(vm, "cat /root/sibling") == "sibling\n", r)
c.call("stop", {"vm": vm})

# Continue, and replace: on a copy of the layer, so the given one is not touched.
copy = work + "/self.layer"
subprocess.run(["/bin/cp", "-cR", layer, copy], check=True)
before = manifest(copy)["id"]
vm, r = boot(copy, **{"continue": True})
check("a layer boots with --continue", vm is not None, r)
check("a second --continue on it is refused", c.call("start", {"image": copy, "continue": True})[0]["result"]["isError"] is True)
sh(vm, "echo replaced > /root/replaced; sync")
c.call("stop", {"vm": vm})
check("stop replaced the layer, which has a new id", manifest(copy)["id"] != before, manifest(copy))
vm, r = boot(copy)
check("and it holds what was written", vm is not None and sh(vm, "cat /root/replaced") == "replaced\n", r)
c.call("stop", {"vm": vm})
vm, r = boot(child)
check("a child made before still boots", vm is not None and sh(vm, "cat /root/marker") == "child\n", r)
c.call("stop", {"vm": vm})
check("no lock file is left", not [f for f in os.listdir(work) if f.endswith(".lock")], os.listdir(work))

# commit mirrors the start options.
def refused(arguments, words):
    r = c.call("commit", arguments)[0]
    return r["result"]["isError"] is True and words in text(r)

vm, r = boot()
check("commit --clone is refused for a VM that did not start with --clone or --continue", refused({"vm": vm, "clone": work + "/x"}, "did not start with"))
check("commit --continue is refused likewise", refused({"vm": vm, "continue": True}, "did not start with"))
check("commit with two ways to save is refused", refused({"vm": vm, "layer": work + "/x", "save": work + "/y"}, "exactly one"))
check("commit --ephemeral with --on-stop is refused", refused({"vm": vm, "ephemeral": True, "on-stop": True}, "no --on-stop"))
r, _ = c.call("commit", {"vm": vm, "save": work + "/viasave"})
check("commit --save saves a child", r["result"]["isError"] is False and manifest(work + "/viasave.layer")["chain"][-1] == parent["id"], r)
c.call("stop", {"vm": vm})

vm, r = boot(layer, save=work + "/cancelled")
check("a VM started with --save boots", vm is not None, r)
check("its target is reserved", c.call("start", {"image": layer, "save": work + "/cancelled"})[0]["result"]["isError"] is True)
r, _ = c.call("commit", {"vm": vm, "ephemeral": True})
check("commit --ephemeral cancels the scheduled save", r["result"]["isError"] is False, r)
c.call("stop", {"vm": vm})
check("and nothing was saved", not os.path.exists(work + "/cancelled.layer"), os.listdir(work))
vm, r = boot(layer, save=work + "/cancelled")
check("and the name was released", vm is not None, r)
c.call("stop", {"vm": vm})
check("and saved this time", os.path.isdir(work + "/cancelled.layer"), os.listdir(work))

vm, r = boot(layer, clone=work + "/viaclone")
check("commit --save is refused for a VM started with --clone", refused({"vm": vm, "save": work + "/x"}, "already holds"))
r, _ = c.call("commit", {"vm": vm, "clone": work + "/now"})
check("commit --clone saves a sibling now", r["result"]["isError"] is False and manifest(work + "/now.layer")["chain"] == parent["chain"], r)
c.call("commit", {"vm": vm, "ephemeral": True})
c.call("stop", {"vm": vm})
check("the --clone save was cancelled", not os.path.exists(work + "/viaclone.layer"), os.listdir(work))

copy2 = work + "/cont.layer"
subprocess.run(["/bin/cp", "-cR", layer, copy2], check=True)
before = manifest(copy2)["id"]
vm, r = boot(copy2, ephemeral=True)
check("a VM started with --continue is needed for commit --continue", vm is not None, r)
c.call("stop", {"vm": vm})
vm, r = boot(copy2, **{"continue": True})
c.call("commit", {"vm": vm, "ephemeral": True})
r, _ = c.call("commit", {"vm": vm, "continue": True})
check("commit --continue replaces the starting layer now", r["result"]["isError"] is False and manifest(copy2)["id"] != before, r)
c.call("stop", {"vm": vm})
shutil.rmtree(copy2)

# A VM running from a layer is not affected when another VM replaces the layer.
pin = work + "/pin.layer"
subprocess.run(["/bin/cp", "-cR", layer, pin], check=True)
watcher, r = boot(pin)
check("a VM boots from a layer", watcher is not None, r)
replacer, r = boot(pin, **{"continue": True})
sh(replacer, "echo replacer > /root/replacer; sync")
c.call("stop", {"vm": replacer})
check("another VM replaced the layer meanwhile", "replacer" in "".join(os.listdir(pin + "/..")) or manifest(pin)["id"] != parent["id"], manifest(pin))
r, _ = c.call("commit", {"vm": watcher, "save": work + "/fromwatcher"})
check("the first VM can still commit", r["result"]["isError"] is False, r)
vm, r = boot(work + "/fromwatcher")
check("and its child boots, without the replacement's changes", vm is not None and sh(vm, "ls /root") == sh(watcher, "ls /root") and "replacer" not in sh(vm, "ls /root"), r)
c.call("stop", {"vm": vm})
c.call("stop", {"vm": watcher})
shutil.rmtree(pin)

# A --continue VM whose layer was moved does not recreate it.
moved = work + "/moved.layer"
subprocess.run(["/bin/cp", "-cR", layer, moved], check=True)
vm, r = boot(moved, **{"continue": True})
check("a --continue VM boots", vm is not None, r)
os.rename(moved, work + "/moved-away.layer")
sh(vm, "echo x > /root/x; sync")
c.call("stop", {"vm": vm})
check("stop does not recreate the moved layer", not os.path.exists(moved), os.listdir(work))
check("and the moved layer is as it was", manifest(work + "/moved-away.layer")["id"] == parent["id"], manifest(work + "/moved-away.layer"))
shutil.rmtree(work + "/moved-away.layer")

# layers lists a layer a running VM will save as pending, until the save is cancelled.
vm, r = boot(layer, save=work + "/pending")
shown = text(c.call("layers")[0])
check("layers lists a layer a running VM will save as pending", f"also pending: {work}/pending.layer (saved when VM {vm} stops)" in shown, shown)
c.call("commit", {"vm": vm, "ephemeral": True})
check("and no longer once the save is cancelled", "pending.layer" not in text(c.call("layers")[0]))
c.call("stop", {"vm": vm})

# A save holds what the guest has written even when it has not flushed: a stop and a commit ask the guest to sync first.
vm, r = boot(layer, save=work + "/flushed-stop")
sh(vm, "echo stop > /root/flush-stop")
c.call("stop", {"vm": vm})
vm, r = boot(work + "/flushed-stop.layer")
check("a stop saves what the guest had not yet written to its disk", vm is not None and sh(vm, "cat /root/flush-stop 2>&1") == "stop\n", r)
c.call("stop", {"vm": vm})
vm, r = boot()
sh(vm, "echo commit > /root/flush-commit")
c.call("commit", {"vm": vm, "save": work + "/flushed-commit"})
c.call("stop", {"vm": vm})
vm, r = boot(work + "/flushed-commit.layer")
check("and so does a commit", vm is not None and sh(vm, "cat /root/flush-commit 2>&1") == "commit\n", r)
c.call("stop", {"vm": vm})

vm, r = boot(**{"tweak": ["linux/alpine-repositories"]})
check("start --tweak runs the tweak before returning", vm is not None, r)
check("a tweak for another OS is refused", c.call("tweak", {"vm": vm, "name": "windows/no-sleep"})[0]["result"]["isError"] is True)
c.call("stop", {"vm": vm})

check("--install with a layer is refused", c.call("start", {"image": layer, "install": "alpine", "ephemeral": True})[0]["result"]["isError"] is True)
check("start without saying what becomes of the work is refused", "becomes of" in text(c.call("start", {"image": layer})[0]))
r, _ = c.call("rm", {"layer": copy})
check("rm removes a layer by path", r["result"]["isError"] is False and not os.path.exists(copy), r)

c.close()
shutil.rmtree(work, ignore_errors=True)
check.finish()
