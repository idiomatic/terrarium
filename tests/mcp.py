"""Protocol checks of `terrarium mcp` that need no VM. Usage: mcp.py BINARY"""
import os, subprocess, sys, tempfile, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from client import Client, Checks, META

binary = sys.argv[1]
# A support directory of its own, so the user's images, VMs, and caches are never touched.
os.environ["TERRARIUM_SUPPORT"] = tempfile.mkdtemp(prefix="terrarium-support-")
check = Checks()
c = Client(binary)

r = c.wait(c.request("tools/list", meta=False))
check("missing _meta is -32602", r and r.get("error", {}).get("code") == -32602, r)

c.send({"jsonrpc": "2.0", "id": 900, "method": "tools/list", "params": {"_meta": {"io.modelcontextprotocol/protocolVersion": "2026-07-28"}}})
r = c.wait(900)
check("missing clientCapabilities is -32602", r and r.get("error", {}).get("code") == -32602, r)

c.send({"jsonrpc": "2.0", "id": 901, "method": "tools/list", "params": {"_meta": {
    "io.modelcontextprotocol/protocolVersion": "1900-01-01", "io.modelcontextprotocol/clientCapabilities": {}}}})
e = (c.wait(901) or {}).get("error", {})
check("unsupported version is -32022 with supported and requested",
      e.get("code") == -32022 and e.get("data", {}).get("supported") == ["2026-07-28"] and e.get("data", {}).get("requested") == "1900-01-01", e)

r = c.wait(c.request("server/discover"))
res = (r or {}).get("result", {})
check("discover: resultType, versions, tools capability, serverInfo, caching",
      res.get("resultType") == "complete" and res.get("supportedVersions") == ["2026-07-28"] and "tools" in res.get("capabilities", {})
      and res.get("_meta", {}).get("io.modelcontextprotocol/serverInfo", {}).get("name") == "terrarium"
      and isinstance(res.get("ttlMs"), int) and res["ttlMs"] >= 0 and res.get("cacheScope") in ("public", "private"), r)

r = c.wait(c.request("tools/list"))
res = (r or {}).get("result", {})
tools = res.get("tools", [])
names = [t["name"] for t in tools]
by = {t["name"]: t for t in tools}
check("tools/list: complete with caching hints", res.get("resultType") == "complete" and isinstance(res.get("ttlMs"), int) and "cacheScope" in res, list(res))
check("tools/list: every verb but run, in order",
      names == ["pull", "images", "rmi", "start", "commit", "stop", "ps", "shot", "logs", "click", "move", "resize", "type", "key", "exec", "tweak", "wait", "put", "get", "clipboard"], names)
check("tool names use only allowed characters", all(all(ch.isalnum() or ch in "_-." for ch in n) and 1 <= len(n) <= 128 for n in names))
check("every inputSchema is an object schema", all(t["inputSchema"].get("type") == "object" for t in tools))
props = by["start"]["inputSchema"]["properties"]
check("start schema: options, recipe enums, integers, boolean license",
      set(props) == {"image", "memory", "cpus", "password", "accept-license", "overlay", "install", "provision", "tweak", "user", "disk", "commit-on-stop"} and "windows" in props["install"]["enum"] and "cloud-init" in props["provision"]["enum"]
      and props["memory"]["type"] == "integer" and props["accept-license"]["type"] == "boolean"
      and props["tweak"]["type"] == "array" and props["tweak"]["items"]["type"] == "string"
      and "required" not in by["start"]["inputSchema"], props)
check("tweak schema: name required, vm",
      by["tweak"]["inputSchema"]["required"] == ["name"] and "vm" in by["tweak"]["inputSchema"]["properties"])
check("exec schema: command required, args array, vm",
      by["exec"]["inputSchema"]["required"] == ["command"] and by["exec"]["inputSchema"]["properties"]["args"]["type"] == "array" and "vm" in by["exec"]["inputSchema"]["properties"])
check("click schema: at is a pattern string", "pattern" in by["click"]["inputSchema"]["properties"]["at"] and by["click"]["inputSchema"]["required"] == ["at"])
check("commit has on-stop as boolean", by["commit"]["inputSchema"]["properties"]["on-stop"]["type"] == "boolean")
check("images and ps are closed objects with nothing required",
      by["images"]["inputSchema"].get("additionalProperties") is False and "required" not in by["images"]["inputSchema"])
check("tools/list order is deterministic", [t["name"] for t in c.wait(c.request("tools/list"))["result"]["tools"]] == names)

check("start's disk schema carries the real limits", props["disk"].get("minimum") == 4 and props["disk"].get("maximum") == 1000, props["disk"])
check("ps has a deceased flag", by["ps"]["inputSchema"]["properties"].get("deceased", {}).get("type") == "boolean", by["ps"]["inputSchema"])
check("move takes a point and a vm", by["move"]["inputSchema"]["required"] == ["at"] and "vm" in by["move"]["inputSchema"]["properties"], by["move"]["inputSchema"])
r, _ = c.call("ps", {"deceased": True})
check("ps with deceased answers with no VM running", r["result"]["isError"] is False, r)
r, _ = c.call("run", {"image": "x"})
check("run is not a tool (-32602)", r and r.get("error", {}).get("code") == -32602, r)
r, _ = c.call("nope", {})
check("unknown tool is -32602", r and r.get("error", {}).get("code") == -32602, r)


# A file with qcow2's magic number: `pull` refuses it before storing anything.
import atexit, shutil
_dir = tempfile.mkdtemp()
atexit.register(shutil.rmtree, _dir, True)
QCOW2 = os.path.join(_dir, "disk.qcow2")
with open(QCOW2, "wb") as f:
    f.write(b"QFI\xfb" + bytes(4096))


def tool_error(name, arguments, expect=None):
    r, _ = c.call(name, arguments)
    ok = r and r["result"]["isError"] is True and (expect is None or expect in r["result"]["content"][0]["text"])
    return ok, r


for label, name, arguments, expect in [
    ("missing argument", "rmi", {}, "missing"),
    ("put without a destination", "put", {"from": "/tmp"}, "to"),
    ("get without a source", "get", {"to": "/tmp"}, "from"),
    ("a non-number wait timeout", "wait", {"timeout": "soon"}, None),
    ("put with no VM", "put", {"from": "/tmp", "to": "/x"}, "no running VM"),
    ("get with no VM", "get", {"from": "/x", "to": "/tmp"}, "no running VM"),
    ("wait with no VM", "wait", {}, "no running VM"),
    ("bad modifier", "key", {"chord": "hyper+n"}, None),
    ("unknown argument", "images", {"bogus": 1}, "bogus"),
    ("non-number memory", "start", {"image": "x", "memory": "many"}, None),
    ("boolean memory", "start", {"image": "x", "memory": True}, None),
    ("bad point", "click", {"at": "10"}, None),
    ("license without --install", "start", {"image": "x", "accept-license": True}, "--install"),
    ("password without --install", "start", {"image": "x", "password": "p"}, "--install"),
    ("user without --install", "start", {"image": "x", "user": "art"}, "--install windows or macos"),
    ("user with an Alpine install", "start", {"image": "x", "install": "alpine", "user": "art"}, "--install windows or macos"),
    ("a user name with a space", "start", {"image": "x", "install": "windows", "user": "a b"}, "--user must be"),
    ("a user name the system has", "start", {"image": "x", "install": "windows", "user": "Administrator"}, "already has"),
    ("user with macOS but no license", "start", {"image": "x", "install": "macos", "user": "art"}, "needs --accept-license"),
    ("license with macOS but no user", "start", {"image": "x", "install": "macos", "accept-license": True}, "needs --user"),
    ("password with macOS but no user", "start", {"image": "x", "install": "macos", "password": "p"}, "needs --user"),
    ("password from stdin is for run only", "start", {"image": "x", "install": "alpine", "password": "-"}, "for run only"),
    ("disk without --install", "start", {"image": "x", "disk": 80}, "--disk applies to --install"),
    ("disk below the default", "start", {"image": "x", "install": "windows", "disk": 20}, "from 40 to 1000"),
    ("disk above the most", "start", {"image": "x", "install": "alpine", "disk": 5000}, "from 4 to 1000"),
    ("disk with a guest", "start", {"image": "/nonexistent.guest", "disk": 80}, "--disk applies to --install"),
    ("install with provision", "start", {"image": "x", "install": "alpine", "provision": "alpine"}, "alternatives"),
    ("an unknown provision recipe", "start", {"image": "x", "provision": "linux-rc"}, "linux-rc"),
    ("install with a guest", "start", {"image": "/nonexistent.guest", "install": "alpine"}, "by itself"),
    ("a guest that does not exist", "start", {"image": "/nonexistent.guest"}, "no such guest"),
    ("neither image nor guest", "start", {}, "missing IMAGE"),
    ("non-boolean license", "start", {"image": "x", "accept-license": "yes"}, None),
    ("a qcow2 image", "pull", {"source": QCOW2}, "qcow2"),
    ("a password with a newline", "start", {"image": "alpine", "install": "alpine", "password": "a\nb"}, "control characters"),
    ("tweak with install", "start", {"image": "x", "install": "alpine", "tweak": ["windows/edge-quiet"]}, "--install"),
    ("tweak with a macOS install and no account", "start", {"image": "x", "install": "macos", "tweak": ["macos/quiet-setup"]}, "--user"),
    ("tweak as a string", "start", {"image": "x", "tweak": "windows/edge-quiet"}, "list of strings"),
    ("an unknown tweak", "tweak", {"name": "nosuch"}, "unknown tweak"),
    ("a tweak with no VM running", "tweak", {"name": "windows/edge-quiet"}, "no running VM"),
    ("tweak needs a name", "tweak", {}, "missing name"),
    ("clipboard needs an action", "clipboard", {}, "missing action"),
    ("clipboard action is get or set", "clipboard", {"action": "cut"}, "expected one of get, set"),
    ("clipboard set needs text", "clipboard", {"action": "set"}, "needs the text"),
    ("clipboard get takes no text", "clipboard", {"action": "get", "text": "x"}, "takes no text"),
    ("an empty vm", "logs", {"vm": ""}, "empty VM ID"),
    ("an empty image", "rmi", {"image": ""}, "empty image"),
]:
    ok, r = tool_error(name, arguments, expect)
    check(label + " is a tool error", ok, r)

check("bogus method is -32601", (c.wait(c.request("bogus/method")) or {}).get("error", {}).get("code") == -32601)
check("ping answers", "result" in (c.wait(c.request("ping", meta=False)) or {}))
c.send({"jsonrpc": "2.0", "id": 902, "method": "tools/call", "params": {"name": "images", "arguments": {}, "_meta": dict(META)}})
r = c.wait(902)
check("a numeric id round-trips", r and r["id"] == 902)
c.send({"jsonrpc": "2.0", "id": "abc", "method": "ping", "params": {}})
r = c.wait("abc")
check("a string id round-trips", r and r["id"] == "abc")
# A slow call that needs no VM: pulling a large (sparse) local file, which is hashed whole.
_slow = os.path.join(tempfile.mkdtemp(), "slow.img")
with open(_slow, "wb") as f:
    f.truncate(1 << 30)
def slow_pull(id):
    c.send({"jsonrpc": "2.0", "id": id, "method": "tools/call", "params": {"name": "pull", "arguments": {"source": _slow}, "_meta": dict(META)}})
notes = []
slow_pull(950)
time.sleep(0.2)
slow_pull(950)
dup = c.wait(950, timeout=5, notifications=notes)
first = dup if dup and "result" in dup else c.wait(950, timeout=120, notifications=notes)
dup = dup if dup and "error" in dup else next((m for m in notes if m.get("id") == 950 and "error" in m), None)
check("a request id already in flight is refused with -32600", dup is not None and dup["error"]["code"] == -32600, dup)
check("and the first call with that id still answers", first is not None and "result" in first, first)
slow_pull(951)
time.sleep(0.2)
c.send({"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {"requestId": 951, "reason": "test"}})
r = c.wait(951, timeout=120)
check("cancelling a tool that is not cancellable still gets its answer", r is not None and "result" in r, r)
for m in (first, r):
    name = ((m or {}).get("result", {}).get("content") or [{}])[0].get("text", "")
    if name and not m["result"].get("isError"):
        subprocess.run([binary, "rmi", name], capture_output=True)
os.unlink(_slow)
os.rmdir(os.path.dirname(_slow))
c.proc.stdin.write("this is not json\n")
c.proc.stdin.flush()
time.sleep(0.5)
parse = None
while not c.lines.empty():
    m = c.lines.get()
    if m.get("error", {}).get("code") == -32700:
        parse = m
check("garbage input is a -32700 parse error with a null id", parse is not None and parse["id"] is None, parse)
check("stdout carried only JSON lines", not c.bad, c.bad)
check("exits when stdin closes", c.close() == 0)

c = Client(binary)
c.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "old", "version": "1"}}})
res = (c.wait(1) or {}).get("result", {})
check("legacy initialize: requested version, tools, serverInfo, no resultType",
      res.get("protocolVersion") == "2025-06-18" and "tools" in res.get("capabilities", {}) and res.get("serverInfo", {}).get("name") == "terrarium" and "resultType" not in res, res)
c.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
c.send({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
r = c.wait(2)
check("legacy tools/list works without _meta", r and len(r["result"]["tools"]) == 20 and "resultType" not in r["result"], r)
c.send({"jsonrpc": "2.0", "id": 3, "method": "initialize", "params": {"protocolVersion": "1999-01-01"}})
r = c.wait(3)
check("legacy initialize with an unknown version answers with one we speak", r and r["result"]["protocolVersion"] == "2025-11-25", r)
check("legacy: exits when stdin closes", c.close() == 0)
import shutil
shutil.rmtree(os.environ["TERRARIUM_SUPPORT"], ignore_errors=True)
check.finish()
