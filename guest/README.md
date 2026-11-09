# guest

Zig code that runs inside guests, embedded in `terrarium` by `build.zig`.

* `helper/`: the static `terrarium-helper`, a vsock listener that runs commands for `exec`, and moves files for `put` and `get`
  * `protocol.zig`: the frame format, with its unit tests (`zig build test`)
  * `unix.zig`: the macOS and Linux side
  * `windows.zig`: the Windows side, over the `viosock` Winsock provider
* `shim/`: `winfb.zig`, the EFI application that gives Windows a linear framebuffer

The scripts that run in a guest (`install.cmd`, `unattend.xml`, `SetupComplete.cmd`, Alpine's `install.start` and `answers`) belong to their recipes and live in `core/recipes/`.
