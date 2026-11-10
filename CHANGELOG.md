# Changelog

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
