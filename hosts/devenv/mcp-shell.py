"""MCP stdio server with one tool, run_command: bash in the working directory.

nixpkgs packages no shell MCP server; the reference servers cover files, git and
the web. This gives the chat agent a shell. It runs in
strata-tools.service's sandbox (hosts/devenv/llm.nix), not as Strata.
"""

import json
import os
import signal
import subprocess
import sys

MAX_TIMEOUT_S = 600
MAX_OUTPUT = 100_000  # characters per stream; the chat servers cut the whole result further

TOOL = {
    "name": "run_command",
    "description": "Run a bash command line in the workspace directory and return its exit code, "
    "stdout and stderr. Non-interactive: stdin is empty.",
    "inputSchema": {
        "type": "object",
        "properties": {
            "command": {"type": "string", "description": "The bash command line"},
            "timeout_s": {
                "type": "number",
                "description": f"Kill the command after this many seconds (default 120, max {MAX_TIMEOUT_S})",
            },
        },
        "required": ["command"],
    },
}


class UnknownMethod(Exception):
    pass


def clip(b: bytes) -> str:
    s = b.decode(errors="replace")
    return s if len(s) <= MAX_OUTPUT else s[:MAX_OUTPUT] + f"\n[... {len(s) - MAX_OUTPUT} more characters cut]"


def run_command(args: dict) -> dict:
    if not isinstance(args.get("command"), str):
        raise ValueError("command: expected a string")
    timeout = max(1.0, min(float(args.get("timeout_s") or 120), MAX_TIMEOUT_S))
    # A session of its own, so a timeout kills everything the command started.
    p = subprocess.Popen(["bash", "-c", args["command"]], stdin=subprocess.DEVNULL,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    try:
        out, err = p.communicate(timeout=timeout)
        note = ""
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        out, err = p.communicate()
        note = f"\n[killed after {timeout:g} s]"
    text = f"exit code: {p.returncode}{note}\n--- stdout ---\n{clip(out)}\n--- stderr ---\n{clip(err)}"
    return {"content": [{"type": "text", "text": text}], "isError": p.returncode != 0}


def handle(msg: dict):
    method, params = msg.get("method"), msg.get("params") or {}
    if method == "initialize":
        return {"protocolVersion": params.get("protocolVersion", "2025-06-18"),
                "capabilities": {"tools": {}}, "serverInfo": {"name": "shell", "version": "1"}}
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": [TOOL]}
    if method == "tools/call" and params.get("name") == TOOL["name"]:
        return run_command(params.get("arguments") or {})
    raise UnknownMethod(f"unknown method or tool: {method} {params.get('name', '')}".strip())


def main():
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            print(json.dumps({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "parse error"}}),
                  flush=True)
            continue
        if "id" not in msg:  # notifications (notifications/initialized, cancelled) need no answer
            continue
        try:
            reply = {"result": handle(msg)}
        except UnknownMethod as e:
            reply = {"error": {"code": -32601, "message": str(e)}}
        except Exception as e:  # a bad argument must not end the server
            reply = {"error": {"code": -32603, "message": f"{type(e).__name__}: {e}"}}
        print(json.dumps({"jsonrpc": "2.0", "id": msg["id"], **reply}), flush=True)


if __name__ == "__main__":
    main()
