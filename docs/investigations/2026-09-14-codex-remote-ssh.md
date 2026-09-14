# Codex ChatGPT Web Remote SSH: partial implementation

Infrastructure revision inspected: `8d6cc94795047d3d2b82a05b11de80a877ec5151` (`indev`).
No NixOS module, firewall, SSH policy, secret, lockfile or deployment was changed.

The live machine is `devenv`, user `develop`, Linux. VS Code's installed
`openai.chatgpt-26.901.22334-linux-x64` extension is already running its bundled
Codex `0.153.0`, with `CODEX_HOME=/home/develop/.codex`. The system CLI is separately
`0.154.0` and was not substituted. The user config is a regular file with built-in
`openai` provider and no top-level bridge URL. It was not modified.

`flake.nix` -> `makeDualExport` -> `makeConfiguration` imports `hosts/devenv.nix`.
That host enables both VS Code Server and nix-ld. `devenvTools.nix` only supplies
fleet tools. No binary launch failure justifies a compatibility change.
Live sshd sets `GatewayPorts no`, with forwarding disabled specifically for the
Docker migration user. The checked-in develop key is unrestricted. Reverse
forwarding with the desktop's actual selected key remains untested.

The current flake has synthetic validation outputs despite older AGENTS.md text:

```bash
# DEVENV — executed successfully; does not activate anything
nix build .#checks.x86_64-linux.devenv --no-write-lock-file --no-link
```

The live `nixosConfigurations.devenv` toplevel fails without external WireGuard
secret metadata, as designed. No missing secret was invented or safety check removed.
No activation command is needed. A future reviewed host change would use
`rebuildHost devenv` after validation; this was not executed.

Bridge source was unavailable locally, so a separate checkout was created at
`/home/develop/projects/codex-chatgpt-web`, upstream revision
`e85e3693fdb4e3e033348c08df0298c20fcdb612`, version `5.0.6`. Its uncommitted work adds
host-independent workspace path validation, regression tests, and a dedicated
foreground desktop SSH tunnel utility with start/stop/status and port discovery.
See that checkout's `docs/remote-ssh-status.md` for commands, acceptance matrix,
source diagnoses, rollback, and validation results.

This is not a completed integration. Desktop OS, installed release, bridge port,
CODEX_HOME and SSH alias were not accessible. Source inspection also found
same-host rollout-history and daemon-token interrupt-hook assumptions. Narrow
remote authenticated context/cancellation and transactional remote installation
remain unimplemented. A shared/untrusted remote host needs authenticated or
per-user-isolated transport; loopback TCP is not authorization.

The desktop installation/browser/MCP setup was not accessed or altered. No live
bridge model, remote Codex task/file operation, resume/compaction, cancellation,
subagent, or local/remote isolation acceptance result is claimed.
