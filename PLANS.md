# Plans

What is not built: what is planned, what is open, and what is not planned, with the measurements behind them. The built model is in [AGENTS.md](AGENTS.md). Requests marked *Biblio* came from an agent driving terrarium over MCP to build Biblio's Windows app, rechecked on 2026-11-10.

## to build

* **`layers` sizes**: unique against shared bytes, from the physical extents (`F_LOG2PHYS_EXT`), so a layer shows what `rm` would free; now DELTA and CHAIN are the allocated bytes of the bundle's own files and of its clones

## open

* **a quiet hang** (*Biblio*): `dotnet build` in a Windows guest once sat idle for 13 minutes with no child process, then ran normally after a kill and a rerun with `-nodeReuse:false`; nothing points at terrarium, but whether the helper's session (a hidden `Start-Process` with redirected output) or its job object keeps MSBuild's reused nodes waiting is not known; if it does, `exec` could set `MSBUILDDISABLENODEREUSE=1` on Windows

## not planned

### layers

* `squash L L`, replacing L in place by swap, as `commit --continue` does: depth comes from `--save` chains, whose squash can take the next name; squashing one layer gains little (1.47 GB to 1.37); it replaces a layer other sessions may use and makes a running `--continue` VM's save fail; `squash L L2`, `rm L`, and a rename do it by hand, and the swap is cheap to add if wanted
* `dedupe [PATH...]`, replacing files of the same bytes with clones of one copy, for a layer that returned from another volume with its own copy of an ancestor: rare, and such a copy now costs only its allocated bytes; proving two files alike safely takes grouping by UUID and size, comparing physical extents, hashes kept in extended attributes, and reading both (size and modification time prove nothing); removing the copy and cloning the layer again with `cp -c` does it by hand
* merging from the root end: a child records its parent's UUID, which a merged layer does not have, so `squash` merges only what is above ANCESTOR
* whether Finder keeps an ASIF file's holes: not tested (Finder could not be scripted), and the advice (`cp -c`, or `cp` across volumes) does not need it
* an ASIF parser or library, for lack of a strong use; the format is documented by the community (<https://github.com/huven/asif-format>, header version 1, CC0), and a throwaway parser read two real layers' chunk counts as `diskutil` did; if one is built, that page is collected in [docs/specifications](docs/specifications/README.md)
* what needs a parser: a `compact` verb (hole punching) and per-chunk fingerprints
* if a parser is built: a partial chunk can have physical chunk 0 (no data of its own), which is the header, and must be skipped (punching it destroyed a copy's header and directories, and `diskutil` then took the copy for a RAW image); work on a clone, verify every sector, then swap

### guests

* **toolchain recipes** (*Biblio*), such as `windows/dotnet` or `windows/zig`, for a build environment saved once: a layer already does it (start, `exec` the installers, `--save`), and recipes would make terrarium pin and follow each toolchain's versions and download sources; tweaks stay settings, safe to run again
* **a project config file** (*Biblio*) naming a default image, memory, tweaks, and setup commands: a project's own script or a line in its docs (`terrarium start LAYER --tweak … --ephemeral`) says as much, while a file would add rules for finding it and a second way to give every option

## measured

On macOS 27, with a Windows and an Alpine guest.

* **UUIDs**: an ASIF file's UUID and stable UUID are in its header and survive a clone, a copy, and the guest's writes (a 50 MB write changed neither), so a differing UUID proves the bytes differ and a matching one proves nothing; the header and the directory sequence numbers did not change across two writes either
* **parent**: a layer records its parent's UUID in its header (offset 0x50)
* **sparse**: an ASIF file is partly sparse on disk (a child layer: 973 MiB long, 438 MiB allocated)
* **chunks**: in a booted Windows child, 24 of 971 written chunks equal the parent's (2.5%), and 498 of 721 partial chunks hold under 128 KiB of valid sectors; punching holes over the invalid 4 KiB runs changed no readable sector (1630 of 1630 chunks identical; the guest booted from it) and freed 79 MiB of 438 (18%)
