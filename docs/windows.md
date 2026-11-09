# Windows guests

## Walkthrough

You need Microsoft's Windows 11 ARM64 ISO from [its download page](https://www.microsoft.com/software-download/windows11arm64); the link expires, so save the file. The first install downloads the virtio-win drivers and builds about 9 GB of installer media once per ISO. The install makes an administrator (`terra`, or the name `--user NAME` gives) with automatic login; `terrarium start` prints its random password once, and `--password PW` chooses it instead (**WARNING:** `/bin/ps` shows it). Pull the ISO once, for the examples below:

```
terrarium pull ~/Downloads/Win11_Arm64.iso
```

**Install.**

```
mkdir -p ~/vms
terrarium run Win11 --install windows \
  --commit-on-stop ~/vms/win-installed
```

The window shows the installer, which types its own commands. When it finishes (about 4 minutes), it shuts the VM down, the window closes, and `--commit-on-stop` saves `~/vms/win-installed.guest`. Then go through Windows' setup phase once, and save the result:

```
terrarium run ~/vms/win-installed.guest \
  --tweak edge-quiet \
  --tweak no-sleep \
  --tweak no-lock \
  --commit-on-stop ~/vms/win
```

1. The first boot takes about 3 minutes and restarts once by itself, then shows Microsoft's license page.
2. Press Accept, and wait for the desktop. The tweaks hide Edge's first-run experience and turn off sleep, the lock screen, and the screen saver once the guest's helper answers, which Windows starts after setup, so press Accept within ten minutes, or `terrarium` stops the VM with an error.
3. Shut Windows down from its Start menu; the window closes and `~/vms/win.guest` is saved.
4. From then on, `terrarium run ~/vms/win.guest` skips that phase.

**Interactive, ephemeral.** Run the finished guest and close the window:

```
terrarium run ~/vms/win.guest
```

Nothing you do is kept: the VM works on a copy of the guest, which is discarded when the VM stops. If the guest wrote to its disk, closing asks first, and *Stop Without Committing* (Command-D) confirms the discard.

**Interactive, persistent.** Add `--commit-on-stop` to keep what you do, which saves a new guest and leaves `~/vms/win.guest` unchanged:

```
terrarium run ~/vms/win.guest \
  --commit-on-stop ~/vms/win-work
```

Closing the window saves `~/vms/win-work.guest`, and the original is untouched. Without the flag, choose *Commit…* (now) or *Commit When VM Stops…* from the *File* menu, or *Commit…* in the closing sheet. Any OS's guest works the same, and a `--tweak` passed to `run` applies as soon as the helper answers, rather than after you have started working.

To keep only what the run changed, as a small layer over the guest, which stays the base, give `--overlay`:

```
terrarium run ~/vms/win.guest \
  --overlay ~/vms/work.overlay \
  --commit-on-stop ~/vms/work
terrarium run ~/vms/win.guest \
  --overlay ~/vms/work-HASH.overlay
```

The first run starts a new layer (`work.overlay` does not exist yet) and saves it as `~/vms/work-HASH.overlay`, where `HASH` is the guest's ID. The second run continues from it, and its changes are discarded when you close the window unless you commit again; the saved overlay is never written to, only a copy of it.

**Headless.**

```
mkdir -p ~/vms
id=$(terrarium start Win11 --install windows --accept-license)
installed=$(terrarium commit $id ~/vms/win-installed --on-stop)
while terrarium ps | grep -q $id; do sleep 10; done
id=$(terrarium start $installed \
       --tweak edge-quiet \
       --tweak no-sleep \
       --tweak no-lock)
ready=$(terrarium commit $id ~/vms/win --on-stop)
terrarium exec shutdown /s /t 0
while terrarium ps | grep -q $id; do sleep 10; done
id=$(terrarium start $ready)
until terrarium exec true 2>/dev/null; do sleep 10; done
terrarium exec cmd /c ver
```

1. The installer shuts the VM down when it finishes (about 4 minutes), which is when the first `--on-stop` saves the installed guest as `~/vms/win-installed.guest`, which boots without the ISO.
2. That guest still has Windows' long "setting up" phase ahead of it: its first boot takes about 3 minutes and restarts once by itself. The second `terrarium start` does that phase once.
3. Its `--tweak`s (`edge-quiet`, `no-sleep`, and `no-lock`) hide Edge's first-run experience and turn sleep, the lock screen, and the screen saver off. `terrarium start` returns once the guest's helper has answered and the tweaks have run, which is also when the saved guest has them.
4. The second `--on-stop` saves the result as `~/vms/win.guest` after a clean shutdown, so the guest you hand off for quick tests or interactive use starts without the wait.
5. `terrarium exec` runs as the account (`terra` unless `--user` says otherwise), elevated, in the auto-logon session.

With `--accept-license`, terrarium accepts Microsoft's terms for that install and says so; without it, Windows stops at its license page, and you press Accept with `terrarium shot > screen.png` and `terrarium click 866,656` (coordinates are pixels of the `terrarium shot` image).

How `--install windows` works, and what it took, is in [core/recipes/windows/README.md](../core/recipes/windows/README.md).
