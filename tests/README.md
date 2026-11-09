# tests

* `layers.py CORE`: the core's layering (see [core/README.md](../core/README.md)); `zig build test` runs it
* `unit/main.swift`: unit checks of the core's helpers, through `@testable import`; `zig build test` runs it
* `mcp.py BINARY`: protocol checks of `terrarium mcp`, no VM needed; `zig build test` runs it
* `pull.py BINARY`: `pull`'s qcow2 conversion and tar extraction on synthetic images (it removes what it stores); `zig build test` runs it
* `live.py BINARY IMAGE`: the same server against a live Alpine VM (a stored image such as `alpine-standard`): wait, exec, put and get, cancellation, concurrency, the clipboard's typed fallback, `shot`, input, `commit`, and `ps` showing `tweaking NAME` while `linux/experimental-sleep` runs
* `live_guest.py BINARY GUEST`: overlays over a saved Linux guest (`NAME.guest`, from `--install alpine`): a new layer, `commit` to `PATH-<guestid>.overlay`, a boot over it, the guest left unchanged, an overlay of another guest refused, and the `linux/alpine-repositories` and `linux/no-blank` tweaks (by `--tweak` and `tweak`, run twice)
* `live_macos.py BINARY GUEST`: the same against a saved macOS guest (`NAME.guest`): the helper runs as `terra` with passwordless `sudo`, the sleep, screen saver, and first-login tweaks run twice, the clipboard round-trips, `shot`, `click`, and `stop` work, and an overlay over the guest commits, boots with its data, and leaves the guest unchanged
* `live_windows.py BINARY GUEST`: the `windows/no-sleep`, `windows/no-lock`, and `windows/edge-quiet` tweaks against a saved Windows guest (`NAME.guest`, from `--install windows --accept-license`): `--tweak` on `start`, each by `tweak` run twice, the registry and power settings changed, and a tweak for another OS refused

`client.py` is the shared stdio client. Run with `python3 -I`.
