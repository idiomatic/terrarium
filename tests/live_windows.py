"""Checks of `terrarium mcp` against a live Windows guest: the tweaks. Usage: live_windows.py BINARY LAYER
LAYER is an installed Windows layer (`NAME.layer`, from `--install windows --accept-license` and `commit`)."""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from client import Client, Checks

binary, layer = sys.argv[1], sys.argv[2]
check = Checks()
c = Client(binary)


def out(r):
    return r["result"]["structuredContent"]["stdout"]


def powershell(vm, script):
    r, _ = c.call("exec", {"vm": vm, "command": "powershell", "args": ["-NoProfile", "-NonInteractive", "-Command", script]})
    return out(r).strip()


def asleep(vm, setting):
    return powershell(vm, "[bool]((powercfg /query SCHEME_CURRENT %s) -match 'Current AC Power Setting Index: 0x00000000')" % setting) == "True"


r, _ = c.call("start", {"image": layer, "tweak": ["windows/no-sleep"], "ephemeral": True}, timeout=600)
vm = r["result"]["structuredContent"]["id"]
check("start --tweak runs the tweak before returning", r["result"]["isError"] is False and len(vm) == 8, r)
check("and it took effect", asleep(vm, "SUB_SLEEP 29f6c1db-86da-48c5-9fdb-f2b67b1f44da"), powershell(vm, "powercfg /query SCHEME_CURRENT SUB_SLEEP"))

for name, script, want in [
        ("windows/no-sleep", "[bool]((powercfg /query SCHEME_CURRENT SUB_VIDEO 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e) -match 'Current AC Power Setting Index: 0x00000000')", "True"),
        ("windows/no-lock", "(Get-ItemProperty 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Personalization').NoLockScreen", "1"),
        ("windows/edge-quiet", "(Get-ItemProperty 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge').HideFirstRunExperience", "1"),
        ("windows/no-toasts", "(Get-ItemProperty 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\CurrentVersion\\PushNotifications').NoToastApplicationNotification", "1"),
        ("windows/no-onedrive", "(Get-ItemProperty 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\OneDrive').DisableFileSyncNGSC", "1"),
        ("windows/no-widgets-copilot", "(Get-ItemProperty 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsCopilot').TurnOffWindowsCopilot", "1"),
        ("windows/no-suggestions", "(Get-ItemProperty 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\CloudContent').DisableWindowsConsumerFeatures", "1"),
        ("windows/no-setup-nags", "(Get-ItemProperty 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\OOBE').DisablePrivacyExperience", "1")]:
    for again in ("", " again"):
        r, _ = c.call("tweak", {"vm": vm, "name": name}, timeout=120)
        check("the %s tweak succeeds%s" % (name, again), r["result"]["isError"] is False, r)
    check("%s took effect" % name, powershell(vm, script) == want, powershell(vm, script))
for again in ("", " again"):
    r, _ = c.call("tweak", {"vm": vm, "name": "windows/trim"}, timeout=700)
    check("the windows/trim tweak succeeds%s" % again, r["result"]["isError"] is False, r)
check("windows/no-lock turns the screen saver off", powershell(vm, "(Get-ItemProperty 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Control Panel\\Desktop').ScreenSaveActive") == "0")
check("a tweak for another OS is refused", c.call("tweak", {"vm": vm, "name": "linux/no-blank"})[0]["result"]["isError"] is True)

r, _ = c.call("stop", {"vm": vm})
check("stop answers", r["result"]["isError"] is False, r)
check("stdout carried only JSON lines", not c.bad, c.bad)
check("exits when stdin closes", c.close() == 0)
check.finish()
