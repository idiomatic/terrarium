# macOS guests

## Walkthrough

You need a macOS restore image (an IPSW) of the macOS this Mac runs; Apple's catalog lists it, and the 27.2 build is 25.6 GB. Keep about 60 GB free: the image, plus about 35 GB while installing (the saved guest is about 26 GB). With `--user USERNAME` and `--accept-license` together, the guest gets that account (a random password, printed by `terrarium start`, or `--password PW` (**WARNING:** `/bin/ps` shows it)), automatic login, and Remote Login; without them it stops at Setup Assistant. Pull the image once, for every example below:

```
terrarium pull https://updates.cdn-apple.com/2026FallFCS/\
c9671975-52db-4fb5-9af2-00217169ba8d/\
UniversalMac_27.2_26B123_Restore.ipsw
```

**Install.** `run` shows the install in a window, and `--save` keeps the result:

```
terrarium run UniversalMac --install macos \
  --user terra --accept-license \
  --tweak quiet-setup \
  --save mac
```

1. The install runs first (`terrarium ps` shows its progress).
2. The window shows the guest logged in as `terra`, with the helper installed, so `terrarium exec` works.
3. `--tweak` with `--install macos` runs once the helper is installed (`terrarium ps` shows `tweaking macos/quiet-setup`). Wait for it to finish before closing the window, since a tweak's change persists only in what you save.
4. Close the window; `--save` saves the root layer `mac`. (Without the flag, choose *Commit…* before closing, or the install is lost.)

Without `--user` and `--accept-license` (which go together), the guest stops at Setup Assistant, where you agree to Apple's license yourself; terrarium then cannot log in to install the helper, so `terrarium exec` and tweaks are not available in that guest, but `terrarium shot`, `terrarium click`, `terrarium type`, and `terrarium key` are.

**Interactive, ephemeral.** Run the layer `mac`:

```
terrarium run mac
```

Everything done in this run is discarded when you close the window (closing asks first if the guest wrote to its disk).

**Interactive, persistent.** Give `--save` to keep what you do, which saves a child of `mac` and leaves it unchanged:

```
terrarium run mac \
  --tweak no-screensaver \
  --save mac-no-screensaver
```

The tweaks run once the helper answers.  Closing the window saves the layer `mac-no-screensaver`. (Or choose *Commit…* before closing.)

**Headless.**

```
id=$(terrarium start UniversalMac --install macos \
       --user terra --accept-license \
       --tweak no-sleep \
       --tweak no-screensaver \
       --tweak quiet-setup \
       --save mac)
while terrarium ps | grep $id | grep -q -e installing -e tweaking; do sleep 10; done
terrarium exec $id sw_vers
terrarium exec $id /sbin/shutdown -h now
```

1. `terrarium start` returns as soon as the install begins, and `terrarium ps` shows its progress as `installing N%`.
2. The VM boots once with the account, and terrarium installs the helper over SSH. From that boot until every tweak has succeeded, `terrarium ps` shows `tweaking`, then `running`; the `while` loop waits out `installing` and `tweaking`, so `terrarium exec` finds the finished guest. If a tweak fails, the VM stops, the loop ends, and `exec` reports no VM.
3. The install leaves the guest's sleep settings, screen saver, and first-login panes alone, so the `--tweak`s name them up front. They run the moment the helper is installed, before anything else touches the guest (`terrarium ps` shows `tweaking TWEAK`): sleep off, the screen saver and its password prompt off, and Setup Assistant's first-login panes marked seen.
4. A failed tweak stops the VM, so a layer that was saved has them all.
5. The saved root layer is a `.layer` bundle, with the machine's identity files; boot it with `terrarium start mac`, and `terrarium rmi UniversalMac` frees the 25.6 GB image.

How `--install macos` works, and what it took, is in [core/recipes/macos/README.md](../core/recipes/macos/README.md).
