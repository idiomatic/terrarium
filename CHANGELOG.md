# Changelog

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
