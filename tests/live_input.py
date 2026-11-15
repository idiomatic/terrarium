"""Checks of held keys and mouse buttons against a live Linux guest, read from its input devices. Usage:
live_input.py BINARY IMAGE_FILE
IMAGE_FILE is a stored cloud image's file (such as `images/alpine-…-cloudinit-….img`), pulled into a temporary support
directory, so the check's VM stays out of yours."""
import os, shutil, struct, subprocess, sys, tempfile, threading, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from client import Client, Checks

binary, source = sys.argv[1], sys.argv[2]
os.environ["TERRARIUM_SUPPORT"] = tempfile.mkdtemp(prefix="terrarium-support-")
work = tempfile.mkdtemp(prefix="terrarium-test-")
check = Checks()
image = subprocess.run([binary, "pull", source], capture_output=True, text=True, check=True).stdout.strip()
c = Client(binary)


def text(r):
    return "".join(b.get("text", "") for b in r["result"]["content"] if b["type"] == "text")


r, _ = c.call("start", {"image": image, "provision": "cloud-init", "ephemeral": True, "memory": 1024}, timeout=300)
vm = r["result"]["structuredContent"]["id"]
c.call("wait", {"vm": vm}, timeout=620)
devices = text(c.call("exec", {"vm": vm, "command": "sh", "args": ["-c", "for d in /sys/class/input/event*; do echo \"${d##*/} $(cat $d/device/name)\"; done"]})[0])
keyboard = next(line.split()[0] for line in devices.splitlines() if "Keyboard" in line)
pointer = next(line.split()[0] for line in devices.splitlines() if "Digitizer" in line)


def events(device, seconds, actions):
    """The EV_KEY events the guest sees on DEVICE while ACTIONS run: (code, value) with value 1 press, 2 repeat, 0 release."""
    # The guest's reader runs on its own client, since a call waits for its command.
    reader = Client(binary)
    thread = threading.Thread(target=reader.call, args=("exec", {"vm": vm, "command": "sh", "args": ["-c", f"timeout {seconds} cat /dev/input/{device} > /tmp/ev"]}), kwargs={"timeout": seconds + 30})
    thread.start()
    time.sleep(1)
    actions()
    thread.join()
    reader.close()
    c.call("get", {"vm": vm, "from": "/tmp/ev", "to": os.path.join(work, "ev")})
    data = open(os.path.join(work, "ev"), "rb").read()
    found = [struct.unpack("<qqHHi", data[i:i + 24])[2:] for i in range(0, len(data) - 23, 24)]
    return [(code, value) for kind, code, value in found if kind == 1]


KEY_X, KEY_Y, CTRL, LEFT, RIGHT = 45, 21, 29, 272, 273
seen = events(keyboard, 4, lambda: c.call("key", {"vm": vm, "chord": "x", "hold": 1500}))
check("key --hold sends a press, the guest's repeats, and a release", seen[0] == (KEY_X, 1) and seen[-1] == (KEY_X, 0)
      and seen.count((KEY_X, 2)) > 10 and seen.count((KEY_X, 1)) == 1, seen)


def across():
    c.call("key", {"vm": vm, "chord": "ctrl+x", "down": True})
    c.call("move", {"vm": vm, "at": "300,300"})
    c.call("shot", {"vm": vm})
    c.call("click", {"vm": vm, "at": "300,300"})
    c.call("key", {"vm": vm, "chord": "ctrl+x", "up": True})


seen = events(keyboard, 12, across)
check("key --down holds a chord across move, shot, and click, until key --up", seen[:2] == [(CTRL, 1), (KEY_X, 1)]
      and seen[-2:] == [(KEY_X, 0), (CTRL, 0)] and all(value == 2 for _, value in seen[2:-2]) and len(seen) > 20, seen[:4] + seen[-4:])

seen = events(pointer, 4, lambda: c.call("click", {"vm": vm, "at": "400,400", "hold": 800}))
check("click --hold presses and releases the button once", [e for e in seen if e[0] == LEFT] == [(LEFT, 1), (LEFT, 0)], seen)


def drag():
    c.call("click", {"vm": vm, "at": "400,400", "down": True})
    c.call("move", {"vm": vm, "at": "500,450", "duration": 300})
    c.call("shot", {"vm": vm})
    c.call("click", {"vm": vm, "at": "500,450", "button": "right"})
    c.call("key", {"vm": vm, "chord": "a"})
    c.call("click", {"vm": vm, "at": "500,450", "up": True})


seen = [e for e in events(pointer, 12, drag) if e[0] in (LEFT, RIGHT)]
check("click --down holds the button across move, shot, another button, and key, until click --up",
      seen == [(LEFT, 1), (RIGHT, 1), (RIGHT, 0), (LEFT, 0)], seen)

c.call("stop", {"vm": vm}, timeout=120)
c.close()
shutil.rmtree(work, ignore_errors=True)
shutil.rmtree(os.environ["TERRARIUM_SUPPORT"], ignore_errors=True)
check.finish()
