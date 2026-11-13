"""Checks of named networks against live Linux guests. Usage: live_network.py BINARY IMAGE_FILE
IMAGE_FILE is a stored cloud image's file (such as `images/alpine-…-cloudinit-….img`), pulled into a temporary support
directory, so the check's networks and VMs stay out of yours."""
import os, shutil, subprocess, sys, tempfile, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from client import Client, Checks

binary, source = sys.argv[1], sys.argv[2]
os.environ["TERRARIUM_SUPPORT"] = tempfile.mkdtemp(prefix="terrarium-support-")
check = Checks()
image = subprocess.run([binary, "pull", source], capture_output=True, text=True, check=True).stdout.strip()
c = Client(binary)


def text(r):
    return "".join(b.get("text", "") for b in r["result"]["content"] if b["type"] == "text")


def boot(network):
    r, _ = c.call("start", {"image": image, "provision": "cloud-init", "ephemeral": True, "memory": 1024, "network": [network]}, timeout=300)
    return (r["result"]["structuredContent"]["id"] if not r["result"]["isError"] else None), r


# A subnet vmnet does not pick by itself is one an earlier, killed holder is unlikely to have left held.
r, _ = c.call("network", {"name": "lab", "subnet": "192.168.233.0/24", "reserve": ["server=192.168.233.10", "client1=192.168.233.11", "client2=192.168.233.12"]})
check("network defines lab with three reservations", r["result"]["isError"] is False, r)

# The clients start before the server, and client2 before client1: the roles, not the order, give the addresses.
vms = {}
for key in ("client2", "client1", "server"):
    vms[key], r = boot("lab:" + key)
    check("start joins lab as " + key, vms[key] is not None, r)
r, _ = c.call("start", {"image": image, "provision": "cloud-init", "ephemeral": True, "network": ["lab:client1"]}, timeout=300)
check("a second VM as client1 is refused, naming the first", r["result"]["isError"] and "already has a VM as client1" in text(r) and vms["client1"] in text(r), text(r))

for key, vm in vms.items():
    r, _ = c.call("addr", {"vm": vm, "network": "lab"}, timeout=120)
    check("addr gives " + key + " its reserved address", text(r) == {"server": "192.168.233.10", "client1": "192.168.233.11", "client2": "192.168.233.12"}[key], text(r))
r, _ = c.call("addr", {"vm": vms["server"]}, timeout=120)
check("addr without a network gives the NAT address", r["result"]["isError"] is False and not text(r).startswith("192.168.233."), text(r))
r, _ = c.call("addr", {"vm": vms["server"], "network": "other"})
check("addr on a network the VM is not on is an error", r["result"]["isError"] and "not on network other" in text(r), r)

r, _ = c.call("exec", {"vm": vms["client1"], "command": "ping", "args": ["-c", "2", "-W", "2", "192.168.233.10"]})
check("client1 reaches the server", r["result"]["isError"] is False, text(r))
r, _ = c.call("exec", {"vm": vms["client2"], "command": "ping", "args": ["-c", "2", "-W", "2", "192.168.233.11"]})
check("client2 reaches client1", r["result"]["isError"] is False, text(r))
check("the Mac reaches the server", subprocess.run(["ping", "-c", "2", "-t", "4", "192.168.233.10"], capture_output=True).returncode == 0)
r, _ = c.call("exec", {"vm": vms["server"], "command": "sh", "args": ["-c", "ip -6 addr | grep -c 'inet6 fd'"]})
check("the guests have IPv6 ULA addresses too", r["result"]["isError"] is False and int(text(r).split()[0]) >= 2, text(r))

shown = text(c.call("ps")[0])
check("ps shows each VM's network and role", all(f"lab:{key}" in shown for key in vms), shown)
r, _ = c.call("network", {"name": "lab", "remove": True})
check("network remove is refused while VMs are on it", r["result"]["isError"] and "up" in text(r), r)

for vm in vms.values():
    c.call("stop", {"vm": vm}, timeout=120)
up = True
for _ in range(10):
    time.sleep(1)
    if "down" in text(c.call("network", {"name": "lab"})[0]):
        up = False
        break
check("the network goes down once no VM is on it", not up)
r, _ = c.call("network", {"name": "lab", "remove": True})
check("then network remove takes it away", r["result"]["isError"] is False, r)

c.close()
shutil.rmtree(os.environ["TERRARIUM_SUPPORT"], ignore_errors=True)
check.finish()
