# `--install windows` recipe

`WindowsRecipe.swift` plans the install (boot disk, answer file, typed keys), `WindowsDrivers.swift` fetches the pinned virtio-win drivers, and `WindowsInstaller.swift` builds the installer media.

`install.cmd` (runs in WinPE), `unattend.xml` (the answer file), and `SetupComplete.cmd` (first boot) are real files; `build.zig` embeds them in the `__TERRARIUM` section, and the recipe fills in their `@INDEX@`, `@USER@`, `@PASS@`, and `@EULA@` placeholders. Section names are at most 16 characters.

## Findings

Findings behind `--install windows`, kept for what the code and [AGENTS.md](../../../AGENTS.md) do not say. Source: the recipe is `core/recipes/windows/`, the shim `guest/shim/winfb.zig`, the helper `guest/helper/windows.zig`. Surveyed: [Running Windows 11 and Server 2025 with macOS Virtualization.framework](https://mustafaakin.dev/blog/windows-on-tart/) and the `windows-guest-extras` branch of `mustafaakin/tart` (nonstandard license: behavior reimplemented, none of its code, scripts, or binaries).

Status (2026-11-06): Windows 11 Pro ARM64 installs unattended from the unmodified Microsoft ISO through `terrarium start --install windows` (207 s), and the installed system (`--overlay`) resets once, is restarted by `terrarium`, and answers `exec` 169 s after the start. The first run downloads the drivers and builds the installer media (about 4 minutes).

### Boot

* **The image cannot be the boot disk's base.** With the ISO at the start of the NVMe disk, the firmware boots Microsoft's boot manager through UDF before the shim, and the VM dies in under a second. Windows boots from a blank sparse base (40 GB unless `--disk` says more).
* **A new EFI variable store at every boot.** Windows registers its own boot entry, so with a kept store the firmware skips the shim and Windows has no display.
* **A failed install looks like a finished one from outside:** both end with `wpeutil shutdown`, so the script stops at its first failed step and leaves `install.ok` on the boot disk only on success (untested against a real failure).
* **The first boot's stop at about 112 s is a guest reset** (the end of specialize), which VZ reports as an error stop on the generic platform.
* **The restart needs the VNC server stopped.** `_VZVNCServer` (has `stop`, `start`, and a settable `virtualMachine`) holds a strong reference to the VM on its queue; until stopped, the next `vm.start` fails with "Internal Virtualization error" (also reproduced with Alpine and Debian).
* **PMU emulation is required:** without it Boot Manager never draws (100% CPU).

### Display

* **Firmware GOP:** it is BltOnly (two handles, 1280x800, no frame buffer), so Boot Manager draws nothing without the shim. The shim patches both GOP `Mode` structs to a linear buffer and copies it with the original `Blt`.
* **Timer events stop once Boot Manager runs;** the shim therefore hooks `ExitBootServices` once instead of using a timer.
* **After ExitBootServices** the display needs `viogpudo`, which takes over at about 60 s (1024x768).
* **Seeing the screen:** use `_VZVNCServer`; the rest failed:
  * `VZVirtualMachineView` layer tree (a blank placeholder `IOSurface`), `cacheDisplay`, `screencapture` (no Screen Recording permission)
  * `-[VZGraphicsDisplay _takeScreenshotWithCompletionHandler:]`: always "Failed to take a screenshot", then the VM enters the error state (also for macOS guests)
  * `_VZLinearFramebufferGraphicsDeviceConfiguration`: on EFI the VM fails to start at every size tried

### Installer environment

* **WinPE:** boots and idles by about 28 s; the boot FAT disk is `C:`; `autounattend.xml` on these USB disks is ignored; the virtio-win ISO is not mounted (copy the driver files to FAT); `drvload` of `viogpudo` succeeds but the WinPE picture does not change, so the install runs blind. `where` and `displayswitch.exe` are absent.
* **Media:** WinPE cannot mount the ISO, hence the FAT32 and exFAT split (`install.wim` is 7.6 GB). `diskutil` alone builds the media; no `hdiutil`.
* Windows opens the Start menu by itself on the first desktop of a fresh install; `Esc` closes it.

### Guest services

* **vsock:** the `viosock` driver install registers the Winsock provider "Virtio Vsock STREAM" (`{9980498C-E732-482B-9F67-924273A56666}`, `viosocklib.dll`); the helper asks the driver for the family number (`CreateFileW(\\.\Viosock)`, `DeviceIoControl 0x0801300C`; 40), binds with CID `-1`, and the host gets `ECONNRESET` until the listener exists. The helper starts as a scheduled task made by `SetupComplete.cmd`.
* **The Windows helper must not use its connection after returning:** a detached thread read it after its stack frame was gone (`0xc0000005` after about five requests). It now closes the socket and joins the thread first. The helper runs as the install's account (`terra` by default), elevated, from an at-logon task in the auto-logon session (the clipboard needs a session; a startup task runs in session 0, which has no desktop), so it is reachable once that logon completes.
* **Network:** NetKVM, DHCP from the VZ NAT.
* **Input** (RFB key and pointer events, screenshot pixel coordinates): left, right, and double click, drag, scroll (button 5), letters, digits, symbols with Shift, `Return`, `Esc`, and Ctrl chords all work. Modifier keysyms are Mac-style: the Windows key is `Alt_L` or `Alt_R`, and Windows' Alt is `Meta_L`; `Super_L`, `Super_R`, and `Hyper_L` do nothing (`terrarium key` maps `win` and `alt` accordingly). Not confirmed: `Meta+F4` on Notepad with unsaved text, a bare `Alt_L` tap opening Start, dragging a desktop icon.
* Installed-system files are readable from the host after the VM stops (`diskutil mount readOnly`).
* **Setup scrubs the cached answer file:** `C:\Windows\Panther\unattend.xml` stays, rewritten after `SetupComplete.cmd`, with each password as `*SENSITIVE*DATA*DELETED*` (checked 2026-11-07); nothing needs deleting.
* **`exec` and background children:** a `start /b` child inherits the output pipes, so the helper reads only what is waiting (`PeekNamedPipe`) and stops shortly after the command exits; the command runs in a job object, started suspended until it is in the job, so a host hang-up ends everything it started.

### Seen, cause unknown

* **Apple's VM service crashed in failed configurations:** 33 `com.apple.Virtualization.VirtualMachine` reports, all `SIGBUS` (`KERN_PROTECTION_FAILURE`) in `memmove` on the `cpu-0` thread, in the ISO-as-base runs and in boot runs before the variable-store and VNC fixes. None since.
* **One early PMU-on crash** (1 s, "Internal Virtualization error") never recurred.
* **Boot can be slow under host memory pressure** (one run sat 18 minutes on "Getting ready").

### Private APIs

* `VZGenericPlatformConfiguration`: `_setPerformanceMonitoringUnitEmulationEnabled:` (required), `_setFineGrainedTrapsEmulationEnabled:`, `_setGuestType:`, `_setVirtualizationHostExtensionEnabled:` (last three unused); called through the Objective-C runtime and guarded with `instancesRespond(to:)`
* `_VZVNCServer` with `_VZVNCNoSecuritySecurityConfiguration`
* unexplored: `VZEFIBootLoader._setROMImageURL:` (a firmware with a built-in framebuffer might replace the shim)

### Gaps

Not verified:

* activation and licensing (the install is unlicensed, with no product key)
* letting Setup partition and apply the image from an answer file (a typed `setup.exe /unattend:C:\...` launch was never tried)
* Windows Server 2025 (no official ARM64 ISO; a public KMS client key in the answer file lets setup finish, per the article)

Limits:

* private APIs can disappear in any macOS update
* no suspend, sound, nested virtualization, or GPU acceleration
* per the article, Microsoft authorizes only Parallels for Windows on Apple silicon; licensing is the user's responsibility.
