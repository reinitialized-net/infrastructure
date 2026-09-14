# Codex ChatGPT Web installed directly on devenv

Installed 2026-09-14 for `develop`, upstream v5.0.6, inspected source
`e85e3693fdb4e3e033348c08df0298c20fcdb612`.

This installation runs the packaged launcher and its embedded browser on devenv.
The virtual display provides a browser-accessible setup UI over Remote SSH.
The earlier desktop-to-remote bridge proposal is separate and was not changed.

## Finish account setup

1. In VS Code Remote SSH, forward remote port **6080** in the Ports panel.
2. Open `http://localhost:6080/vnc.html` (use the assigned local port if different).
3. Retrieve the VNC password in the remote terminal:
   `~/.local/bin/codex-web-headless password`.
4. Select English, complete any ChatGPT browser verification and sign in inside
   the embedded browser. Credentials stay in the user's private browser profile.
5. Run the launcher's browser smoke test, then Install models.
6. For normal coding tools, complete the MCP page's full-harness setup: create
   the OpenAI tunnel and runtime API key through the guided setup; enable ChatGPT
   Developer Mode and configure the `Codex Native2` tunnel connector as upstream
   requires. Enter credentials directly in the launcher, not in chat or this repo.
7. Run Verify runtime, reload the Remote SSH VS Code window, and select a
   `ChatGPT Web` model. Verify a read-only task in a disposable workspace before
   relying on editing, cancellation, or resumed-task behavior.

The launcher reports browser-only mode without this full-harness setup; that mode
cannot supply the normal local filesystem/shell tools. Account setup is not yet
complete, and no successful model turn or tool call is claimed.

## Installed components

- Official checksum-verified AppImage:
  `~/.local/lib/codex-web-gpt/5.0.6/Codex Web GPT.AppImage`.
- SHA-256: `da93ff4b5f02228f6b1883cd941d8da44203070e25daad79306c0da773aef9b9`.
- Independent source checkout: `~/.local/share/codex-chatgpt-web/source`.
- Nix tools and GC root: `~/.local/share/codex-chatgpt-web/tools`.
- Reproducible pinned tool expression and launch scripts:
  `~/.local/share/codex-chatgpt-web/headless/`.
- User systemd target: `codex-web-headless.target`; services:
  `codex-web-display`, `codex-web-window-manager`, `codex-web-launcher`,
  `codex-web-vnc`, and `codex-web-web`.
- Private X display `:97`, authenticated VNC on loopback `5970`, noVNC on
  `127.0.0.1:6080`. X TCP listening is disabled.
- Launcher runs through Nix `appimage-run` with `--disable-gpu` for the virtual
  display. Chromium sandboxing was not disabled.
- User lingering enabled for `develop`; target enabled under `default.target`.

Normal usage stays inside Remote SSH Codex after account setup. The setup page
can be closed while the launcher runs. Reopen it for login challenges or setup.
The launch script pins v5.0.6; launcher upgrades need a corresponding path update
and restart of `codex-web-launcher.service`.

## Operations

```bash
~/.local/bin/codex-web-headless status
~/.local/bin/codex-web-headless restart
~/.local/bin/codex-web-headless stop
journalctl --user -u codex-web-launcher.service
# Rebuild the pinned Nix tool environment if needed:
nix build --impure --file ~/.local/share/codex-chatgpt-web/headless/tools.nix \
  --out-link ~/.local/share/codex-chatgpt-web/tools
```

To stop persistence: `systemctl --user disable --now codex-web-headless.target`.
If models were installed later, remove the integration from launcher Settings
before stopping it, so Codex's route is restored using upstream's journal.
Preserve private browser data unless intentionally resetting the login.
Lingering was previously disabled; disable it only if no other user services
need it: `sudo loginctl disable-linger develop`.

## Validation and boundaries

- Upstream installer checked the published SHA-256 checksum.
- Pinned Nix tool environment built successfully.
- User unit verification passed; all five services run after target restart.
- noVNC HTML returns HTTP 200; WebSocket RFB handshake authenticated successfully
  and returned the expected 1440x1000 display. Unauthenticated RFB access is not
  offered. Listener inspection confirmed loopback-only VNC and web ports.
- Launcher renderer and embedded ChatGPT page were observed through local CDP.
  The initial ChatGPT page requested browser verification.
- No account sign-in, account smoke test, installed model, model turn, MCP tool
  operation, compaction, or cancellation has been verified yet.
- Boot enablement and lingering were verified; no host reboot was performed.
- Existing Codex configuration, host NixOS modules, firewall, flake lock and
  existing uncommitted work were left intact. No fleet activation was necessary.

Upstream setup: https://github.com/miuuyy/codex-chatgpt-web#quick-start
