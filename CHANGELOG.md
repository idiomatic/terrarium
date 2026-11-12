# Changelog

## 0.3.0 (2026-11-12)

### Added

* `squash LAYER NEWLAYER [--onto ANCESTOR]` saves a layer that reads as LAYER but
  descends from ANCESTOR (default: the chain's root), with no VM; starting a layer
  more than 32 deep suggests it
* `start` and `run` take `--by NAME`, who started the VM (default `window`, `cli`,
  or `mcp:CLIENT:PID`), and `ps` shows it as BY, marking the caller's own over MCP
* `exec --timeout SECONDS` kills the command after that long, with a line on stderr
  and status 124
* a `--continue` save of a VM that wrote nothing no longer replaces the layer (it kept
  no change but got a new `id`): `commit --continue` says `unchanged`, and a stop
  notes it

### Changed

* the MCP server's instructions tell an agent that a VM the user runs in a window
  (`run`) is in `ps` and can be observed and driven alongside the user

### Fixed

* a layer saved or started across volumes no longer takes its whole length on disk:
  the copy keeps an ASIF file's holes; and `--clone` or `--continue` from a layer on
  another volume no longer fails to copy its delta
* a long `click --scroll` (about 1,800 notches or more) no longer fails with "the
  VM sent no reply": the client waits as long as the scroll takes, and a real
  timeout says "the VM did not reply within N seconds"

## 0.2.0 (2026-11-10)

### Changed (incompatible)

* every verb that acts on a VM takes it first, as `VERB VM [REMAINDER]` (`exec VM
  COMMAND`, `shot VM`, `stop VM`, `commit VM LAYER`), with no default: the `--vm`
  option and the fallback to the only running VM are gone, and the MCP argument
  is `vm` for `stop` and `commit` too (it was `id`), required on every VM tool

### Added

* `layers` lists a layer a running VM will save, under its parent and marked
  `(saved when VM ID stops)`, and marks one it will replace
* a save no longer misses what the guest has not flushed: before a `commit`, or a
  stop with a save scheduled, terrarium asks the guest to write its disk
* CI: a release's notes are the changelog's section for its version, so the
  section must exist before the tag is pushed

## 0.1.0 (2026-11-10)

First release.

* boots macOS, Windows, Linux (Alpine, Debian, Fedora, and Ubuntu), and other
  guests on Apple silicon with the Virtualization framework, and drives them
  from the command line or from an agent: screenshots, clicks, typing, keys,
  `exec`, `put` and `get`, and the clipboard
* the verbs are also a stdio MCP server, `terrarium mcp`
* installs from ISOs and restore images (`--install`) or readies a live image
  (`--provision`), then saves what a VM does as stackable layers (`--save`,
  `--clone`, `--continue`, `commit`, `layers`, and `rm`)
* tweaks quiet a guest's settings and prompts (`tweak` and `--tweak`)
* `terrarium version` and `--version` print the version
* CI on a macOS 27 arm64 runner, and a `v*` tag publishes a release
