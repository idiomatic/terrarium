# Windows guests

## Walkthrough

You need Microsoft's Windows 11 ARM64 ISO from [its download page](https://www.microsoft.com/software-download/windows11arm64); the link expires, so save the file. The first install downloads the virtio-win drivers and builds about 9 GB of installer media once per ISO. The install makes an administrator (`terra`, or the name `--user USERNAME` gives) with automatic login; `terrarium start` prints its random password once, and `--password PW` chooses it instead (**WARNING:** `/bin/ps` shows it). Pull the ISO once, for the examples below:

```
terrarium pull ~/Downloads/Win11_Arm64.iso
```

**Install.**

```
terrarium run Win11 --install windows \
  --save win-root
```

The window shows the installer, which types its own commands. When it finishes (about 4 minutes), it shuts the VM down, the window closes, and `--save` saves the root layer `win-root` in the layer store. Then go through Windows' setup phase once, and save the result as a child:

```
terrarium run win-root \
  --tweak edge-quiet \
  --tweak no-sleep \
  --tweak no-lock \
  --save win
```

1. The first boot takes about 3 minutes and restarts once by itself, then shows Microsoft's license page.
2. Press Accept, and wait for the desktop. The tweaks hide Edge's first-run experience and turn off sleep, the lock screen, and the screen saver once the guest's helper answers, which Windows starts after setup, so press Accept within ten minutes, or `terrarium` stops the VM with an error. That applies when the install did not have `--accept-license`; with it, the setup phase showed no license page in testing, and the ten minutes are only how long `start` waits for the helper.
3. Shut Windows down from its Start menu; the window closes and the layer `win` is saved.
4. From then on, `terrarium run win` skips that phase, and `win-root` stays as it was, a base for other children.

**Interactive, ephemeral.** Run the finished layer and close the window:

```
terrarium run win
```

Nothing you do is kept: the VM writes to a delta of its own, which is discarded when the VM stops. If the guest wrote to its disk, closing asks first, and *Stop Without Committing* (Command-D) confirms the discard.

**Interactive, persistent.** Give `--save` to keep what you do, which saves a child of `win` and leaves it unchanged:

```
terrarium run win --save win-work
```

Closing the window saves the layer `win-work`. Without the flag, choose *Commit…* (now) or *Commit When VM Stops…* from the *File* menu, or *Commit…* in the closing sheet. A `--tweak` passed to `run` applies as soon as the helper answers, rather than after you have started working. To keep working in `win-work` itself, use `--continue` (or `--clone` for a sibling); see [Layers](layers.md).

**Headless.**

```
id=$(terrarium start Win11 --install windows --accept-license \
       --save win-root)
while terrarium ps | grep -q $id; do sleep 10; done
id=$(terrarium start win-root \
       --tweak edge-quiet \
       --tweak no-sleep \
       --tweak no-lock --save win)
terrarium exec $id shutdown /s /t 0
while terrarium ps | grep -q $id; do sleep 10; done
id=$(terrarium start win --ephemeral)
terrarium wait $id --timeout 900
terrarium exec $id cmd /c ver
```

1. The installer shuts the VM down when it finishes (about 4 minutes), which is when `--save` saves the root layer `win-root`, which boots without the ISO.
2. That layer still has Windows' long "setting up" phase ahead of it: its first boot takes about 3 minutes and restarts once by itself. The second `terrarium start` does that phase once.
3. Its `--tweak`s (`edge-quiet`, `no-sleep`, and `no-lock`) hide Edge's first-run experience and turn sleep, the lock screen, and the screen saver off. `terrarium start` returns once the guest's helper has answered and the tweaks have run, which is also when the saved layer has them.
4. The second `--save` saves the result as `win` after a clean shutdown, so the layer you hand off for quick tests or interactive use starts without the wait.
5. `terrarium exec` runs as the account (`terra` unless `--user` says otherwise), elevated, in the auto-logon session.

With `--accept-license`, terrarium accepts Microsoft's terms for that install and says so; without it, Windows stops at its license page, and you press Accept with `terrarium shot > screen.png` and `terrarium click 866,656` (coordinates are pixels of the `terrarium shot` image).

How `--install windows` works, and what it took, is in [core/recipes/windows/README.md](../core/recipes/windows/README.md).

## Good to know

* **Disk use.** `--disk` (40 GB by default) is the guest's size, not what it takes: the disk is sparse, and a clean install uses about 16 GB. A guest with a development toolchain on it took about 23 GB.
* **The network.** The guest gets its address and DNS from the NAT's DHCP. Setting the adapter's DNS servers (`Set-DnsClientServerAddress`) and resetting it left one guest on a `169.254.x.x` address until `Restart-NetAdapter`; leave DHCP and DNS alone. A lookup of `api.nuget.org` also failed once through the guest's resolver while other names resolved.
* **Display size.** The guest comes up at 1024x768, and its display driver's *Display resolution* setting is greyed out, so a `shot` is at most 1024 pixels wide. Checked on 2026-11-09 in a throwaway boot of a fresh guest, without a fix: Windows sees two monitors on the one Red Hat VirtIO GPU, `\\.\DISPLAY2`, the primary, at 1024x768 (what the host's VNC server shows), and `\\.\DISPLAY1` at 1280x800 to its right, which is the one size the driver lists. `ChangeDisplaySettingsEx` answers success for 1280x800 and changes nothing; making DISPLAY1 the primary failed when applied. The virtio-win dynamic-resolution agent (`vgpusrv.exe -i`, with `viogpuap.exe`, both copied to `C:\Windows\System32`; the install does not include them) installed and ran, and `terrarium resize` still changed nothing. The driver's `FlexResolution` is already 1. So there is no `--display WxH` yet.
* **Long commands.** `exec` ends the command when its connection ends, and a client may give up on a long call (a build of several minutes) first. Start the command detached, writing a log, and read the log with `get` or a short `exec`; the command must leave the job that `exec` ran it in, which is not tested here for Windows.
