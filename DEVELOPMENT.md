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

A push that changes only docs can skip CI with `[skip ci]` in its last commit's message; run `zig build test` first, since that skips CI's docs check too.

## Next

### To build

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

## Measurements

What was found about ASIF layers on macOS 27, with a Windows and an Alpine guest, beyond what the built features record:

* **UUIDs**: an ASIF file's UUID and stable UUID are in its header and survive a clone, a copy, and the guest's writes (a 50 MB write changed neither), so a differing UUID proves the bytes differ and a matching one proves nothing. The header and the directory sequence numbers did not change across two writes either.
* **Parent**: a layer records its parent's UUID in its header, at offset 0x50.
* **Sparseness**: an ASIF file is partly sparse on disk (a child layer: 973 MiB long, 438 MiB allocated).
* **Chunks**: in a booted Windows child, 24 of 971 written chunks equal the parent's (2.5%), and 498 of 721 partial chunks hold under 128 KiB of valid sectors. Punching holes over the invalid 4 KiB runs changed no readable sector (1630 of 1630 chunks identical, and the guest booted from it) and freed 79 MiB of 438 (18%).
