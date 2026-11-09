# cli

The `terrarium` executable: a command line and an MCP server over the verbs in [core](../core/README.md), with the window from [ui](../ui/README.md) for `run`.

| File | Holds |
|---|---|
| `main.swift` | sets the support directory (`$TERRARIUM_SUPPORT`) and the window, then runs the verb |
| `Parse.swift` | the command line's arguments |
| `Help.swift` | `terrarium help` |
| `mcp/MCP.swift` | `terrarium mcp` |
| `Info.plist` | the bundle name the menu bar shows, embedded by `build.zig` |
| `terrarium.entitlements` | the Virtualization entitlement `build.zig` signs with |
