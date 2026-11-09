"""Checks of `terrarium mcp` against a live Linux VM. Usage: live.py BINARY IMAGE
IMAGE is a stored Alpine image (`alpine-standard`), booted with --provision alpine."""
import base64, os, subprocess, sys, tempfile, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from client import Client, Checks

binary, image = sys.argv[1], sys.argv[2]
check = Checks()
work = tempfile.mkdtemp(prefix="terrarium-test-")


def text(r):
    return "".join(b.get("text", "") for b in r["result"]["content"] if b["type"] == "text")


def out(r):
    return r["result"]["structuredContent"]["stdout"]


c = Client(binary)
r, _ = c.call("images")
check("images lists the stored image", image.split("-")[0] in text(r), r)

r, notes = c.call("start", {"image": image, "provision": "alpine", "memory": 1024, "cpus": 2}, timeout=90, progress="tok1")
vm = r["result"]["structuredContent"]["id"]
check("start returns the VM id as text and structured", r["result"]["isError"] is False and r["result"]["content"][0]["text"] == vm and len(vm) == 8, r)
check("ps shows it", vm in text(c.call("ps")[0]))

for _ in range(30):
    r, _ = c.call("exec", {"command": "true"})
    if not r["result"]["isError"]:
        break
    time.sleep(2)
check("the helper answers", not r["result"]["isError"], r)
import re
for _ in range(15):
    shown = re.search(r"\b(\d+)x(\d+)\b", text(c.call("ps")[0]))
    if shown:
        break
    time.sleep(2)
check("ps shows the guest's display size", shown and shown.group(0) == "1280x800", text(c.call("ps")[0]))

r, _ = c.call("exec", {"command": "sh", "args": ["-c", "echo out; echo err >&2; exit 3"]})
s = r["result"]["structuredContent"]
check("exec: streams and status separate; non-zero is an error",
      r["result"]["isError"] is True and s["stdout"] == "out\n" and s["stderr"] == "err\n" and s["exitStatus"] == 3, r)
check("exec: text carries stdout, stderr, and the status", "out" in text(r) and "stderr:\nerr" in text(r) and "exit status 3" in text(r), text(r))
r, _ = c.call("exec", {"command": "sh", "args": ["-c", "echo \"$(nproc) $(grep MemTotal /proc/meminfo | tr -s ' ' | cut -d' ' -f2)\""]})
cpus, kb = out(r).split()
check("--memory and --cpus took effect (2 CPUs, about 1 GiB)", cpus == "2" and 900000 < int(kb) < 1100000, r)
r, _ = c.call("exec", {"command": "no-such-command-xyz"})
check("exec: a missing command is an error with the message", r["result"]["isError"] is True and "not found" in text(r), r)
r, _ = c.call("exec", {"command": "sh", "args": ["-c", "head -c 2000000 /dev/zero | tr '\\0' x"]}, timeout=60)
s = r["result"]["structuredContent"]
check("exec: output is cut at 1 MiB and flagged", s["truncated"] is True and len(s["stdout"]) == 1 << 20, (s["truncated"], len(s["stdout"])))
r, _ = c.call("exec", {"command": "printf", "args": ["%s|%s|", "a b", ""]})
check("exec: args pass through unchanged", out(r) == "a b||", r)
r, _ = c.call("exec", {"command": "sh", "args": ["-c", "yes | head -1"]})
check("exec: commands get SIGPIPE's default action (no broken-pipe errors)", out(r) == "y\n" and r["result"]["structuredContent"]["stderr"] == "", r)
t0 = time.time()
r, _ = c.call("exec", {"command": "sh", "args": ["-c", "sleep 300 & echo started"]}, timeout=30)
check("exec: returns when the command exits, though a background child still holds its output",
      r is not None and out(r) == "started\n" and time.time() - t0 < 5, (time.time() - t0, r))
c.call("exec", {"command": "pkill", "args": ["-x", "sleep"]})
r, _ = c.call("exec", {"command": "true", "vm": "zzzz"})
check("exec: an unknown vm is a tool error", r["result"]["isError"] is True and "no running VM" in text(r), r)

# Alpine here has no graphical session, so it has no clipboard: get fails, and set falls back to typing.
r, _ = c.call("clipboard", {"action": "get"})
check("clipboard get: a guest with no clipboard is an error", r["result"]["isError"] is True and "no clipboard" in text(r), r)
r, _ = c.call("clipboard", {"action": "set", "text": "hi"})
check("clipboard set: typed when the guest has no clipboard, and says so", r["result"]["isError"] is False and "typed" in text(r), r)
r, _ = c.call("clipboard", {"action": "set", "text": "h\u00e9"})
check("clipboard set: text that cannot be typed is refused", r["result"]["isError"] is True and "cannot be typed" in text(r), r)
r, _ = c.call("clipboard", {"action": "set", "text": "x" * 5000})
check("clipboard set: text over 4 KiB is not typed", r["result"]["isError"] is True and "too much to type" in text(r), r)

block = c.call("shot")[0]["result"]["content"][0]
check("shot: an image block with a PNG",
      block["type"] == "image" and block["mimeType"] == "image/png" and base64.b64decode(block["data"])[:8] == b"\x89PNG\r\n\x1a\n")
for name, args in [("type", {"text": "hello"}), ("key", {"chord": "ctrl+c"}), ("click", {"at": "100,100", "button": "right"})]:
    r, _ = c.call(name, args)
    check(name + " answers ok", r["result"]["isError"] is False and text(r) == "ok", r)
check("logs returns the console log", c.call("logs")[0]["result"]["isError"] is False)

id = c.request("tools/call", {"name": "exec", "arguments": {"command": "sh", "args": ["-c", "trap '' TERM; sleep 600; true"]}})
time.sleep(2)
check("a long exec is running in the guest", out(c.call("exec", {"command": "pgrep", "args": ["-x", "sleep"]})[0]).strip() != "")
c.send({"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {"requestId": id, "reason": "test"}})
check("a cancelled request gets no response", c.wait(id, timeout=4) is None)
time.sleep(2)
check("cancelling killed the process and what it started, though it ignores SIGTERM", out(c.call("exec", {"command": "pgrep", "args": ["-x", "sleep"]})[0]).strip() == "")

# A cancellation sent at once, before the exec has reached the guest, still stops it.
id = c.request("tools/call", {"name": "exec", "arguments": {"command": "sleep", "args": ["601"]}})
c.send({"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {"requestId": id, "reason": "test"}})
check("an immediately cancelled exec gets no response", c.wait(id, timeout=4) is None)
time.sleep(2)
check("and nothing of it runs in the guest", out(c.call("exec", {"command": "pgrep", "args": ["-x", "sleep"]})[0]).strip() == "")

slow = c.request("tools/call", {"name": "exec", "arguments": {"command": "sleep", "args": ["4"]}})
time.sleep(0.5)
t0 = time.time()
c.call("ps")
check("a quick call is answered while a slow exec runs", time.time() - t0 < 2.0, time.time() - t0)
done = c.wait(slow, timeout=15)
check("and the slow one still completes", done is not None and done["result"]["isError"] is False, done)

r, _ = c.call("commit", {"id": vm, "path": work + "/snap"})
saved = text(r)
check("commit saves PATH-<hash>.overlay and says where",
      r["result"]["isError"] is False and saved.startswith(work + "/snap-") and saved.endswith(".overlay") and os.path.exists(saved), r)
check("commit refuses an existing file", c.call("commit", {"id": vm, "path": work + "/snap"})[0]["result"]["isError"] is True)
r, _ = c.call("commit", {"id": vm, "path": work + "/later", "on-stop": True})
check("commit with on-stop schedules it", r["result"]["isError"] is False and "later-" in text(r), r)
t0 = time.time()
r, _ = c.call("stop", {"id": vm})
check("stop returns the id promptly (the server reaps the owner)", text(r) == vm and time.time() - t0 < 5, (text(r), time.time() - t0))
time.sleep(1)
check("the on-stop save happened", any(f.startswith("later-") for f in os.listdir(work)), os.listdir(work))
check("ps is empty afterward", vm not in text(c.call("ps")[0]))
# `ps` shows `tweaking NAME` while a tweak runs, and `running` once `start` has returned.
starter = subprocess.Popen([binary, "start", image, "--provision", "alpine", "--memory", "1024", "--tweak", "linux/experimental-sleep"],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
seen = ""
for _ in range(180):
    shown = text(c.call("ps")[0])
    if "tweaking linux/experimental-sleep" in shown:
        seen = shown
        break
    if starter.poll() is not None:
        break
    time.sleep(0.5)
started, errors = starter.communicate(timeout=120)
check("ps shows tweaking NAME while a tweak runs", seen != "", (shown, errors))
check("start with --tweak returned only after the tweak, with the VM's id", starter.returncode == 0 and len(started.strip()) == 8, (starter.returncode, started, errors))
tweaked = started.strip()
shown = text(c.call("ps")[0])
check("and ps shows it running afterward", tweaked in shown and "tweaking" not in shown, shown)
c.call("stop", {"id": tweaked})
check("stdout carried only JSON lines", not c.bad, c.bad)
check("exits when stdin closes", c.close() == 0)

for f in os.listdir(work):
    os.remove(os.path.join(work, f))
os.rmdir(work)
check.finish()
