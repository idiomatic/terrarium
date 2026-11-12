# tests

* `layers.py CORE`: the core's layering (see [core/README.md](../core/README.md)); `zig build test` runs it
* `unit/main.swift`: unit checks of the core's helpers, through `@testable import`; `zig build test` runs it
* `mcp.py BINARY`: protocol checks of `terrarium mcp`, no VM needed; `zig build test` runs it
* `docs.py ROOT`: the Markdown docs' relative links and anchors, and no stale per-verb VM flag; `zig build test` runs it
* `pull.py BINARY`: `pull`'s qcow2 conversion and tar extraction on synthetic images (it removes what it stores); `zig build test` runs it
* `live.py BINARY IMAGE`: the same server against a live Alpine VM (a stored image such as `alpine-standard`): wait, exec (and its timeout), put and get, cancellation, concurrency, the clipboard's typed fallback, `shot`, input, `commit` (a layer, and one scheduled for the stop), and `ps` showing `tweaking NAME` while `linux/experimental-sleep` runs
* `live_guest.py BINARY LAYER`: layers over a saved Linux layer (`NAME.layer`, e.g. a provisioned image saved with `commit`): save (a child with the parent's chain and the parent, by `commit`), `--clone` (a sibling with the same chain, saved at stop), a stop and a commit saving a file the guest never flushed, `layers` listing a layer a running VM will save,  `--continue` on a copy (a new `id`, a child made before still boots; a repeat commit with nothing written leaves it as it is), a second VM aiming at the same layer refused, a VM unaffected when another replaces its layer, `commit` with each start option's words (the refusals, `--ephemeral` cancelling a save and releasing its name, `--clone` and `--continue` now), and no lock file left, the `linux/alpine-repositories` tweak, `--install` with a layer refused, and `rm` by path
* `live_macos.py BINARY LAYER`: against a saved macOS layer (`NAME.layer`): the helper runs as `terra` with passwordless `sudo`, the sleep, screen saver, and first-login tweaks run twice, the clipboard round-trips, `shot`, `click`, and `stop` work, and a child of the layer commits with the machine's identity files, boots, and holds what was written, while the layer itself does not
* `live_windows.py BINARY LAYER`: the `windows/no-sleep`, `windows/no-lock`, `windows/edge-quiet`, `windows/no-toasts`, `windows/no-onedrive`, `windows/no-widgets-copilot`, `windows/no-suggestions`, `windows/no-setup-nags`, and `windows/trim` tweaks against a saved Windows layer (`NAME.layer`, from `--install windows --accept-license`): `--tweak` on `start`, each by `tweak` run twice, the registry and power settings changed, and a tweak for another OS refused

CI runs `zig build test` only; the `live*.py` checks need VMs and run by hand.

`client.py` is the shared stdio client. Run with `python3 -I`.
