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

`ps` tells the VMs apart by who started them (BY): `window` for the user's `terrarium run`, `cli` for `terrarium start`, and `mcp:CLIENT:PID` for each MCP server's, so one server's VMs are not another's even when both serve the same client. Over MCP, `ps` marks the caller's own with `*` and, in `structuredContent`, `mine`. A script that cleans up after itself can pass `--by NAME` to `start` and stop only the VMs whose BY is NAME. BY is a label, not a permission: any session can still stop any VM. A restarted server has a new PID, so the VMs it started before are no longer marked as its own.

VMs outlive the server. `terrarium exec` returns stdout, stderr, and the exit status, and a client's cancellation kills the guest's process. [Verbs](verbs.md) has the verbs' examples, and a command too long for a client's patience should run detached (see its Observe and control section).
