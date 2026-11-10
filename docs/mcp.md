# Use it from an agent

`terrarium mcp` serves every verb but `terrarium run` as an MCP tool on stdin and stdout; [AGENTS.md](../AGENTS.md#mcp) says what the server does. A client configuration:

```
{"command": "terrarium", "args": ["mcp"]}
```

Claude Code, in a project's `.mcp.json` (or `claude mcp add terrarium -- terrarium mcp`):

```
{
  "mcpServers": {
    "terrarium": {"command": "terrarium", "args": ["mcp"]}
  }
}
```

OpenCode, in `opencode.json`:

```
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "terrarium": {"type": "local", "command": ["terrarium", "mcp"], "enabled": true}
  }
}
```

Use the full path to `terrarium` if it is not on the client's `PATH`. A session starts with `pull`, `start`, and `wait`; then `exec`, `put`, `get`, and `shot` drive the guest.

Other sessions may share the Mac's terrarium, so a client does well to prefer the VMs it started, pass them as `vm`, and save what it makes as a new layer instead of replacing one (see [Layers](layers.md)). The server's instructions say so.

VMs outlive the server. `terrarium exec` returns stdout, stderr, and the exit status, and a client's cancellation kills the guest's process. [Verbs](verbs.md) has the verbs' examples, and a command too long for a client's patience should run detached (see its Observe and control section).
