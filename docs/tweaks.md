# Tweaks

A tweak is an OS-specific script, embedded in `terrarium` and run in the guest through the helper. [AGENTS.md](../AGENTS.md) holds the requirements; this page is the catalog, and the authority for each tweak's description and timeout.

```
terrarium tweak windows/no-sleep
terrarium start LAYER --ephemeral --tweak macos/no-sleep --tweak macos/no-screensaver
```

`TWEAK` is `<os>/<name>`, or a bare `<name>`. Where the guest's OS is known (`tweak` on a running VM, `--tweak` on a layer or an install), a bare name is that OS's own tweak, so `no-sleep` works on both Windows and macOS guests; elsewhere it must belong to only one OS. A change persists only if you then `commit` the layer.

## Catalog

| Name | What it does | Timeout |
|---|---|---|
| [`windows/edge-quiet`](../core/tweaks/windows/edge-quiet.ps1) | hides Microsoft Edge's first-run experience (`HKLM\SOFTWARE\Policies\Microsoft\Edge`, `HideFirstRunExperience`) | 60 s |
| [`windows/no-sleep`](../core/tweaks/windows/no-sleep.ps1) | turns display and system sleep and hibernation off (`powercfg`); no recipe does | 60 s |
| [`windows/no-lock`](../core/tweaks/windows/no-lock.ps1) | turns off the lock screen and screen saver (`NoLockScreen`, `ScreenSaveActive` policies) | 60 s |
| [`windows/no-toasts`](../core/tweaks/windows/no-toasts.ps1) | turns off toast notifications (`NoToastApplicationNotification` policy, and the account's `ToastEnabled`) | 60 s |
| [`windows/no-onedrive`](../core/tweaks/windows/no-onedrive.ps1) | keeps OneDrive from running (`DisableFileSyncNGSC` policy, its `Run` entries in `HKCU`, `HKLM`, and the default user's hive) and stops it now | 60 s |
| [`windows/no-widgets-copilot`](../core/tweaks/windows/no-widgets-copilot.ps1) | turns off the taskbar's Widgets, Copilot, and Chat, and Search highlights (policies, and the account's `Explorer\Advanced` values) | 60 s |
| [`windows/no-suggestions`](../core/tweaks/windows/no-suggestions.ps1) | turns off Start recommendations, tips, Spotlight, and promoted apps (`CloudContent` policies, and the account's `ContentDeliveryManager` values) | 60 s |
| [`windows/no-setup-nags`](../core/tweaks/windows/no-setup-nags.ps1) | turns off the first-logon animation and the "Let's finish setting up" and welcome prompts (`OOBE` policy, `ScoobeSystemSettingEnabled`) | 60 s |
| [`windows/trim`](../core/tweaks/windows/trim.ps1) | tells the virtual disk which blocks the guest has freed (`Optimize-Volume -ReTrim`), so a layer saved after it holds only what is in use | 600 s |
| [`linux/trim`](../core/tweaks/linux/trim.sh) | the same with `fstrim -av` (`fstrim -v /` where that fails, as with BusyBox); refused without `fstrim` | 300 s |
| [`macos/no-sleep`](../core/tweaks/macos/no-sleep.sh) | turns display, system, and disk sleep off (`pmset`); no recipe does | 10 s |
| [`macos/no-screensaver`](../core/tweaks/macos/no-screensaver.sh) | turns off the account's screen saver and its password prompt | 10 s |
| [`macos/quiet-setup`](../core/tweaks/macos/quiet-setup.sh) | marks the account's first-login panes as seen (`com.apple.SetupAssistant`) | 10 s |
| [`linux/no-blank`](../core/tweaks/linux/no-blank.sh) | stops the text console blanking, and at every boot through `/etc/local.d` where there is one | 10 s |
| [`linux/ubuntu-no-welcome`](../core/tweaks/linux/ubuntu-no-welcome.sh) | closes the Welcome to Ubuntu window of a live session, waiting up to 50 s for it to open; refused without the `ubuntu-desktop-bootstrap` snap | 60 s |
| [`linux/alpine-repositories`](../core/tweaks/linux/alpine-repositories.sh) | points `/etc/apk/repositories` at the main and community repositories of its first mirror (the CDN when none); refused on a guest without apk | 10 s |
| [`linux/experimental-sleep`](../core/tweaks/linux/experimental-sleep.sh) | sleeps 20 s so a test can see `ps` show `tweaking TWEAK` | 60 s |

A Windows tweak asks for a longer timeout because a cold PowerShell takes some seconds to start.

## Failure

A tweak fails when it exits non-zero, cannot run, or outlasts its timeout (it and what it started are killed). `tweak` then exits with its status (124 for a timeout); `start` and `run` stop the VM, exit 1, and show the tweak's output. An unknown name, or one for another OS, is a usage error (exit 2 from `tweak`).

## Writing one

Add `core/tweaks/<os>/<name>.ps1` (Windows) or `.sh` (Linux and macOS). The leading comment lines (after any shebang) are the header: the first says what it does; later `key: value` lines are settings, of which `timeout: SECONDS` is the first. Unknown keys are ignored.

```sh
# Turns off the thing.
# timeout: 30
defaults write com.example.app thing -bool false
```

A tweak must be safe to run again and gets no stdin. `build.zig` embeds it; only embedded tweaks run, never paths.
