# `--install macos` recipe

`MacRecipe.swift` plans the install (restore image, first-boot provisioning options) and `MacHelperInstall.swift` installs the helper over SSH once the guest is up. The macOS VM itself is configured in [vm/config/MacVM.swift](../../vm/config/MacVM.swift) and driven by [owner/OwnerMac.swift](../../owner/OwnerMac.swift).

## Findings

Findings behind `--install macos`, kept for what the code and [AGENTS.md](../../../AGENTS.md) do not say. Source: the recipe is `core/recipes/macos/`, the VM `core/vm/config/MacVM.swift` and `core/owner/OwnerMac.swift`.

Status (2026-11-06): macOS 27.2 (26B123) installs unattended from the restore image through `terrarium start --install macos --user terra --accept-license` (about 6 minutes), and the saved guest boots by its path to the auto-logged-in desktop and answers `exec`.

### The helper

* **The helper is a LaunchAgent in `terra`'s session** (`gui/501`), so `exec` runs as `terra` and reaches the desktop (`screencapture`, `open`, `osascript`). It starts only once `terra` is logged in (auto-login is on). With auto-login off the guest waits at the login window with no helper (`exec` fails: "helper is not reachable"); logging in with `click` on the password field, then `type` of the password and a newline, started it within about 10 seconds.
* **`terra` has passwordless `sudo`** (`/etc/sudoers.d/terrarium`, checked with `visudo -cf`).
* **Sleep is on** until `--tweak macos/no-sleep` (`pmset -a displaysleep 0 sleep 0 disksleep 0`), then `commit` to keep it; `shot` still nudges the pointer, which wakes a display that sleeps anyway.
* **Replacing the helper's binary under a running helper** makes macOS kill it (`OS_REASON_CODESIGNING`); the install script boots the agent out first, and falls back to `kickstart -k` when `bootstrap` reports an I/O error.
* **The guest's address** comes from `/var/db/dhcpd_leases` by MAC address; stale leases from earlier VMs are common, so a lease is trusted only for the guest's own MAC.

### Prompts and banners

* **Permissions cannot be pre-granted.** Screen Recording (for `screencapture`) and Automation (for `osascript` driving Finder) live in the TCC database, which System Integrity Protection protects. The first use raises a prompt that needs a person (or `shot`, `click`, and `type`); the password field needs a click before `type`. After the grant, `screencapture` worked within seconds; one earlier failure 4 seconds after a grant was not reproduced with a restart-free helper. A grant survives re-signing the helper at the same path.
* **"App Background Activity" banners** appear only when macOS first registers the helper (a new install, or a replaced binary at the same path), because Background Task Management then marks the item `notified` (`sfltool dumpbtm`); later boots log "found existing item" and post nothing. They can cover System Settings toggles during that first session, and the item cannot be pre-registered (the database is SIP-protected).

### The guest as a machine

* **No serial console:** `logs` is empty and Window > Console Log is disabled.
* **Reboots clear `/tmp`**, so a guest saved there is lost.
* **Disk space:** each install writes 20 to 30 GB (an installed guest is about 26 to 30 GB). Two installs ended silently with the data volume near 99% full; the cause was not confirmed.
* **Display size:** `shot` has returned 1280x720, 1280x800, and 2560x1600 in different sessions; unexplained here, see [The display's size](../../README.md#the-displays-size) for what the framebuffer reports.

### Not verified

* Completing Setup Assistant by hand after an install without `--user` and `--accept-license`.
