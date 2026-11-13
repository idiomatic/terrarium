# Development

How terrarium is built, tested, and released, and what comes next. The requirements are in [AGENTS.md](AGENTS.md), and how the parts work is in [core/README.md](core/README.md).

## Building

```
zig build
```

This builds the guest helpers in Zig, the Swift modules, and `zig-out/bin/terrarium`, with the helpers linked in and signed with the virtualization entitlement. It needs macOS 27 on Apple silicon, Xcode, and Zig 0.17 or later; nothing from Homebrew.

## Testing

```
zig build test
```

This runs everything that needs no VM: the core's layering, its unit checks, the MCP server's protocol, `pull`'s conversions, and the docs' links. CI runs the same on every push. The `live*.py` checks boot real guests, so they run by hand; [tests/README.md](tests/README.md) lists what each covers and what it needs.

Set `TERRARIUM_SUPPORT` to a temporary directory to keep a test's images, layers, and VMs out of your own.

## Releasing

1. Set the version in `cli/Version.swift` and `cli/Info.plist` (`tests/mcp.py` checks that they and the MCP server agree).
2. Rename the changelog's Unreleased section to `X.Y.Z (DATE)`; the release's notes are that section, and a tag without one fails.
3. Commit, tag `vX.Y.Z`, and push both. CI checks the tag against the version, builds, tests, and publishes `terrarium-vX.Y.Z-macos-aarch64.tar.gz` with its SHA-256.

CI skips a push or pull request that changes only documentation (Markdown, SVG, and `docs/`), and with it the docs check, so run `zig build test` before pushing one. A tag push always runs.

## Next

### To build

* **Held VNC sessions**, so a VM's display is driven and read over connections that last, not one per call (today each `click`, `move`, `type`, and `key` connects, authenticates, and waits 0.1 s before closing, and `shot` connects for each of up to nine samples). Two phases, the first independent of the second:
  * **Phase 1, held input** (the easier): one connection per VM, held by the owner for `click`, `move`, `type`, `key`, and `shot`'s wake nudge. It only sends events and never asks for the screen, so it keeps no framebuffer; a lock serializes calls, so concurrent ones do not interleave; a failed write, or a new port after a Windows reset, reconnects and sends again. The 0.1 s wait before closing goes, since the server takes events in order, and the button state stays with one connection. For other apps that make many quick calls.
  * **Phase 2, a mirror**: one connection per VM keeps an incremental whole-screen request outstanding and applies each update to a framebuffer (as `RFB.follow` does for `record`). It replaces the size watcher's connection (desktop-size notices come with it, and it reconnects after a reset as that does), and a recording reads its frames instead of connecting.
  * **`shot` from the mirror** (phase 2): after the second's wait since input, it waits until no update has come for 300 ms (at most about 2.4 s), then copies the framebuffer under a lock and encodes it; updates covering under about 0.1% of the screen (a blinking caret, a clock) do not count, so they cannot keep it waiting. During a reset it waits for the mirror or says the display is not ready.
  * Costs of phase 2: a framebuffer per VM (16 MB at 2560×1600), and traffic only while the screen changes (3.4 MB of raw pixels in 6 s with the pointer always moving, none when still). To check first: that the mirror matches a fresh connection's full frame, live and in a test, since it is only as true as the server's tracking of changes.
* **`layers` sizes**: each layer's unique bytes against those it shares, from the physical extents (`F_LOG2PHYS_EXT`), so `layers` shows what `rm` would free. Today DELTA and CHAIN are the allocated bytes of a bundle's own files and of its clones.

### Open

* **A quiet hang**: `dotnet build` in a Windows guest once sat idle for 13 minutes with no child process, then ran normally after a kill and a rerun with `-nodeReuse:false`. Nothing points at terrarium, but it is not known whether the helper's session (a hidden `Start-Process` with redirected output) or its job object keeps MSBuild's reused nodes waiting. If it does, `exec` could set `MSBUILDDISABLENODEREUSE=1` on Windows.
* **Live checks leave files behind**: one `live*.py` check, which moves a `--continue` VM's layer away, uses the real support directory, so each run leaves the VM's files in `unsaved/`. It should run with `TERRARIUM_SUPPORT` set, or remove them.

### Not planned

Layers:

* **`squash L L`**, replacing L in place by swap, as `commit --continue` does. Depth comes from `--save` chains, whose squash can take the next name; squashing a single layer gains little (1.47 GB to 1.37); and it would replace a layer other sessions may use and make a running `--continue` VM's save fail. `squash L L2`, `rm L`, and a rename do it by hand, and the swap is cheap to add if wanted.
* **`dedupe`**, replacing files of the same bytes with clones of one copy, for a layer that came back from another volume with its own copy of an ancestor. It is rare, such a copy costs only its allocated bytes, and proving two files alike safely takes grouping by UUID and size, comparing physical extents, hashes kept in extended attributes, and reading both (size and modification time prove nothing). Removing the copy and cloning the layer again with `cp -c` does it by hand.
* **Merging from the root end**: a child records its parent's UUID, which a merged layer would not have, so `squash` merges only what is above ANCESTOR.
* **Whether Finder keeps an ASIF file's holes**: not tested, since Finder could not be scripted, and the advice in [docs/layers.md](docs/layers.md) does not depend on it.
* **An ASIF parser**, for lack of a strong use. The format is documented by the community (<https://github.com/huven/asif-format>, header version 1, CC0), and a throwaway parser read two real layers' chunk counts as `diskutil` did; if one is built, collect that page in [docs/specifications](docs/specifications/README.md). Only a parser would allow a `compact` verb (punching holes) or per-chunk fingerprints. A partial chunk can have physical chunk 0, which is the header, and must be skipped: punching it destroyed a copy's header, and `diskutil` then took the copy for a RAW image. Work on a clone, check every sector, then swap.

Guests (requests from an agent driving terrarium over MCP to build a Windows app):

* **Toolchain recipes** such as `windows/dotnet` or `windows/zig`. A layer already does it (start, `exec` the installers, `--save`), and recipes would tie terrarium to each toolchain's versions and download sources. Tweaks stay settings that are safe to run again.
* **A project config file** naming an image, memory, tweaks, and setup commands. A project's own script, or a line in its docs (`terrarium start LAYER --tweak … --ephemeral`), says as much; a file would add rules for finding it and a second way to give every option.

Recording:

* **Sound in recordings.** A synthesized click sound, as Camtasia, ScreenFlow, and Screen Studio add from a sample, would be noise in a quiet video; `--clicks` shows clicks instead. The guest's own sound cannot be taken from Virtualization, whose only output sink plays on the Mac's speakers: a Core Audio process tap on the VM's process (`CATapDescription`, muted to the speakers) could capture it, but it needs the System Audio Recording permission, a sound device added at start (`start --audio`, against running VMs without audio), and a virtio sound driver, which Windows on ARM may lack; and guests rarely sound on a click.

## Measurements

What was found about ASIF layers on macOS 27, with a Windows and an Alpine guest, beyond what the built features record:

* **UUIDs**: an ASIF file's UUID and stable UUID are in its header and survive a clone, a copy, and the guest's writes (a 50 MB write changed neither), so a differing UUID proves the bytes differ and a matching one proves nothing. The header and the directory sequence numbers did not change across two writes either.
* **Parent**: a layer records its parent's UUID in its header, at offset 0x50.
* **Sparseness**: an ASIF file is partly sparse on disk (a child layer: 973 MiB long, 438 MiB allocated).
* **The VNC server's address**: `_VZVNCServer` listens on `*:PORT` and has no initializer or property for an address; from inside a guest, the VM network's gateway (`192.168.64.1`) reached it. Binding its listening socket to `lo0` (`IPV6_BOUND_IF`, found by its port and no peer, since `SO_ACCEPTCONN` is unsupported) succeeded and filtered nothing: the kernel applies a bound interface to incoming packets only on interfaces that restrict receiving. VNC authentication is what keeps it closed: offered only security type 2, a wrong answer gets no further.
* **The VNC server's frames**: a Windows guest draws its pointer into the framebuffer; a macOS guest's is not in it, and the server sends no cursor shape even when the cursor pseudo-encoding is asked for. A still screen sends no update at all; with the pointer moving 60 times a second, updates came about 12 a second (84 ms apart), as small rectangles (3.4 MB of raw pixels in 6 s).
* **Chunks**: in a booted Windows child, 24 of 971 written chunks equal the parent's (2.5%), and 498 of 721 partial chunks hold under 128 KiB of valid sectors. Punching holes over the invalid 4 KiB runs changed no readable sector (1630 of 1630 chunks identical, and the guest booted from it) and freed 79 MiB of 438 (18%).
