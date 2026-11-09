"""A minimal MCP stdio client for testing `terrarium mcp`. Every stdout line must be one JSON object."""
import json, os, queue, subprocess, threading, time

META = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {},
    "io.modelcontextprotocol/clientInfo": {"name": "test", "version": "0"},
}


class Client:
    def __init__(self, binary):
        self.proc = subprocess.Popen([binary, "mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL, text=True, bufsize=1)
        self.lines = queue.Queue()
        self.bad = []
        self.next_id = 1
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.proc.stdout:
            try:
                self.lines.put(json.loads(line))
            except ValueError:
                self.bad.append(line)

    def send(self, message):
        self.proc.stdin.write(json.dumps(message) + "\n")
        self.proc.stdin.flush()

    def request(self, method, params=None, meta=True, id=None, progress=None):
        id = id if id is not None else self.next_id
        self.next_id += 1
        params = dict(params or {})
        if meta:
            params["_meta"] = dict(META)
            if progress is not None:
                params["_meta"]["progressToken"] = progress
        self.send({"jsonrpc": "2.0", "id": id, "method": method, "params": params})
        return id

    def wait(self, id, timeout=30, notifications=None):
        """The response with this id; other messages are appended to `notifications`."""
        end = time.time() + timeout
        while time.time() < end:
            try:
                message = self.lines.get(timeout=0.2)
            except queue.Empty:
                continue
            if message.get("id") == id and ("result" in message or "error" in message):
                return message
            if notifications is not None:
                notifications.append(message)
        return None

    def call(self, name, arguments=None, timeout=30, **kw):
        notes = []
        id = self.request("tools/call", {"name": name, "arguments": arguments or {}}, **kw)
        return self.wait(id, timeout, notes), notes

    def close(self):
        self.proc.stdin.close()
        try:
            return self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            return None


class Checks:
    def __init__(self):
        self.failures = []

    def __call__(self, name, ok, detail=""):
        print(("PASS " if ok else "FAIL ") + name + ("" if ok else "  -> " + str(detail)[:300]))
        if not ok:
            self.failures.append(name)

    def finish(self):
        print("\n%d failure(s)" % len(self.failures))
        raise SystemExit(1 if self.failures else 0)
