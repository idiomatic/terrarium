# Changelog

## Unreleased

### Added

* named networks: `start --network NAME[:KEY]` adds a second card on a private
  network that VMs share with each other and the Mac, keeping the NAT card; KEY
  names the VM's role, and `network NAME --reserve KEY=IP` fixes its address;
  `addr VM [NETWORK]` prints a VM's address for scripts; Linux guests get DHCP on
  the new card by the `linux/network-dhcp` tweak
* `start --retina` and `run --retina`: a 2560x1600 guest display drawn at 2x, sharp
  in a `run` window on a Retina screen at the usual size; macOS and GNOME guests
  (by the new `linux/gnome-scale-2x` tweak); not Windows
* held input: `key` and `click` take `--hold MS`, and `--down` and `--up` to hold
  a key or mouse button across other calls, for anything that responds to
  holding one down; the guest repeats a held key as for a physical keyboard

### Fixed

* a VM started with `--continue` that was committed while it ran could not save
  again: its save when it stopped failed, and its work went to `unsaved/`
* `stop` could hang when a commit's pause failed, answered `ok` when the scheduled
  save failed, gave no answer to a second `stop`, and gave up after 10 s on a VM
  still saving
* work that could not be moved to `unsaved/` was deleted; it now stays in
  `vms/<id>/`
* a macOS install was saved without asking the guest to write its disk first
* `ps` could remove a VM that was still starting, and the cleanup of abandoned
  files could remove a layer or image with `.partial.` and a number in its name
* two VMs could both reserve one layer name if one released it as the other took
  it; cancelling a save in the window kept its name reserved
* a VNC connection that failed while connecting closed its descriptor twice, which
  could close another connection's; an MCP cancel or `exec --timeout` arriving as a
  command ended could cut another call's connection the same way
* a `pull` that failed held its scratch file's space until the MCP server exited
* a `record` whose start timed out kept recording with nothing to stop it
* `shot` encodes only the frame it returns, not each sample it compares, so it
  is quicker, most of all on a large display
* a VM that failed before it ran (a bad layer, say) could leave `start` saying only
  "the VM's process exited"; it now says why
* `exec` on a Linux or macOS guest now kills a command that closed its output when
  the caller goes away or `--timeout` runs out; before, it was left running
* two `put`s to one guest path at once could mix their files; now the file that
  lands is one of them, whole
* the guest helper no longer spins when it cannot accept connections, and on
  Windows it can no longer end the wrong process as a command finishes; `exec`
  answers with an error, not silence, when waiting on the guest fails, and a
  helper that stalls partway through a frame no longer holds `exec` past
  `--timeout`; the host also refuses clipboard text over 1 MiB from the guest
* tweaks and the Windows install no longer hide a failed step: the Windows
  install stops when its drivers or its registry change fail, the Windows tweaks
  keep a key's other values and check each `powercfg`, the macOS and Linux tweaks
  fail when a command does, and `linux/ubuntu-no-welcome` fails when the window
  never opens; `linux/network-dhcp` waits 60 s in all, not per card, and
  `linux/gnome-scale-2x` no longer scales the login screen instead of the session;
  `macos/no-screensaver` and `macos/quiet-setup` no longer time out just after boot

## 0.4.0 (2026-11-12)

### Added

* `record VM PATH` writes a video of the screen (H.264, `.mov` or `.mp4`) until
  `record VM --stop`, `--max-seconds`, or the VM stops; a still screen adds no
  frames; the pointer is drawn for guests that do not draw it, `--clicks` marks each
  click with a dot and a ring, and `--crop X,Y,W,H` keeps part of the screen
* input at human speed: `type --interval MS` pauses between characters,
  `move --duration MS` and `click --duration MS` glide the pointer, and
  `click --drag-to X,Y --duration MS` drags at that pace

### Fixed

* security: a VM's screen could be seen and driven, with no password, from any
  machine on the network and from any guest, since the VNC server terrarium reads
  it from listens on every address; it now asks for a random password that only
  the VM's own process knows
* the MCP `shot` note no longer says a macOS guest's pointer is in the image

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
