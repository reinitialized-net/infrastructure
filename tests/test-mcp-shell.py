#!/usr/bin/env python3
"""hosts/devenv/mcp-shell.py over stdio: handshake, tool list, a command, a failure, a timeout.

    python3 tests/test-mcp-shell.py
"""

import json
import subprocess
import sys
import time
from pathlib import Path

SERVER = Path(__file__).resolve().parents[1] / "hosts/devenv/mcp-shell.py"


def main():
    p = subprocess.Popen([sys.executable, str(SERVER)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    n = 0

    def rpc(method, params=None):
        nonlocal n
        n += 1
        p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": n, "method": method, "params": params or {}}) + "\n")
        p.stdin.flush()
        reply = json.loads(p.stdout.readline())
        assert reply["id"] == n, reply
        return reply

    init = rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "t"}})
    assert init["result"]["capabilities"] == {"tools": {}}, init
    p.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")  # no reply
    assert [t["name"] for t in rpc("tools/list")["result"]["tools"]] == ["run_command"]

    ok = rpc("tools/call", {"name": "run_command", "arguments": {"command": "echo out; echo err >&2"}})["result"]
    text = ok["content"][0]["text"]
    assert not ok["isError"] and "exit code: 0" in text and "out\n" in text and "err\n" in text, text

    bad = rpc("tools/call", {"name": "run_command", "arguments": {"command": "exit 3"}})["result"]
    assert bad["isError"] and "exit code: 3" in bad["content"][0]["text"], bad

    # The timeout kills the whole session, including a background child holding the pipes.
    t0 = time.monotonic()
    slow = rpc("tools/call", {"name": "run_command", "arguments": {"command": "sleep 30 & sleep 30", "timeout_s": 1}})
    assert time.monotonic() - t0 < 10 and "killed after 1 s" in slow["result"]["content"][0]["text"], slow

    assert rpc("tools/call", {"name": "nope", "arguments": {}})["error"]["code"] == -32601
    assert rpc("tools/call", {"name": "run_command", "arguments": {}})["error"]["code"] == -32603  # no command
    p.stdin.close()
    assert p.wait(5) == 0
    print("mcp-shell: ok")


if __name__ == "__main__":
    main()
