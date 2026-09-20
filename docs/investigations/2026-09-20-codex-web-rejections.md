# Codex Web GPT rejections on devenv

Investigated on devenv, 2026-09-20. Evidence covers 2026-09-14 through 2026-09-19.
Runtime: Codex Web GPT 5.0.8, Codex CLI 0.154.0, full harness, connector
`Codex Native2 devenv`, tunnel `tunnel_6aa96a85d4508191a9566fe333fae7f6`.
The desktop keeps its own `Codex Native2` connector and tunnel; both connectors
are intentional and were left in place.

## What "rejection" is, by the numbers

Browser-turn failure reasons from the launcher log (`~/.config/Codex Web GPT/logs/`):

| Reason | 09-15 | 09-16 | 09-17 |
| --- | --- | --- | --- |
| ChatGPT rate limit: too many requests | 26 | 16 | 29 |
| Turn aborted (parent turn ended, token retired) | 5 | 0 | 18 |
| Composer rejected plain-text edit / multipart stage timeout | 0 | 2 | 12 |
| Browser stage timeouts, page errors, controls unavailable | 6 | 23 | 20 |

In addition, the ChatGPT model itself reported dozens of tool calls "rejected by the
automatic safety check" / "blocked before execution" in Codex session rollouts. Those calls
never reach the local tunnel: the tunnel log shows 1,754 forwarded calls with only 21
`codex_exec` errors locally, so the block happens upstream in ChatGPT.

## Root causes, in order of devenv-specific impact

### 1. The devenv connector was created from a locally patched runtime (devenv-only)

Timeline:

- 2026-09-14 15:04: a patched 5.0.6 build (`c31c2bb`, "Expose canonical task context and
  local capability status") replaced the launcher runtime. It added a `codex_turn_status` MCP
  tool and extra prompt rules referring to it.
- 2026-09-15 15:57Z: tunnel isolation created the dedicated devenv tunnel and the
  `Codex Native2 devenv` connector while that patched build was the active MCP server.
  ChatGPT captured the patched tool catalog for that connector identity.
- 2026-09-16 23:56 / 2026-09-17 00:19: the runtime moved to stock 5.0.8, which has no
  `codex_turn_status` (`versions/5.0.8-linux-x64/app/cli.js` contains 0 references).

Result: ChatGPT still advertises a tool the server does not have. The tunnel log records
62 calls with `"tool":"unknown"`, all on or after 2026-09-17, every one failing in under
10 ms. The model narrates this as "the requested tunnel status call is unavailable in the
active tool registry". Upstream explicitly says ChatGPT caches the MCP contract per connector
identity and that a stale connector schema can worsen safety decisions; its guidance for
every safety-block report (#423, #446, #449, #489) is to create a fresh connector for the
current mode rather than refreshing the old one.

The desktop connector was created from a release build, so it never had this drift.

### 2. OpenAI-side safety classifier (upstream, not fixable locally)

"This tool call was blocked by OpenAI's safety checks" and "couldn't determine the safety
status" are applied by ChatGPT before dispatch. Upstream closed the reports as `not_planned`
and will not bypass them. Two things make devenv hit it more often:

- Compound commands. Nearly every rejected call in the rollouts is a pipeline or `&&`
  chain (`nl -ba ... | sed -n`, `rg ... | head`, Python wrappers). Narrow single commands
  in the same sessions pass.
- `approval_policy = "never"` with `danger-full-access`. OpenAI's guidance notes that with
  this combination a sensitive action may not create a reviewable approval request, so the
  classifier decides alone. Every devenv rollout since 09-15 used this pair.

### 3. Parallel subagent fan-out trips ChatGPT rate limits

Peak concurrent browser turns reached 5 on 09-15 and 09-17 (Codex `multi_agent` with
`agents.max_depth = 2`, both "Managed by codex-chatgpt-web"). Rate-limit failures cluster
when 3 to 5 tabs are active. When a parent turn then dies, its children are interrupted,
the broker retires their tokens, and any in-flight ChatGPT call reports
"turn token is invalid, expired, or revoked" (`broker claim received ... valid=false`).
That message is a consequence of the abort, not a separate fault.

### 4. Bigger Context, enabled 2026-09-16 16:52Z

Composer rejections and multipart-stage timeouts only appear after this switch. Upstream
issue #541 confirms ChatGPT began returning HTTP 413 `message_length_exceeds_limit` for
large staged payloads from 2026-09-16; a fix is committed but unreleased as of 09-19.

## What was not the cause

- Connector selection: the browser worker requires exactly one row matching the configured
  name, and the diagnostics show `exactSelectedConnectorCount: 1` for `Codex Native2 devenv`.
- Tunnel or broker health: `/healthz` and `/readyz` stayed ready; the MCP server answered
  1,158 `codex_exec` calls successfully.
- The headless Xvfb / appimage-run wrapper: no failures correlate with display or GPU noise.

## Remediation

1. Recreate the devenv connector (account-level, ChatGPT UI, cannot be scripted from
   devenv): ChatGPT Settings, Apps and Connectors, delete `Codex Native2 devenv`, create a
   new connector with that exact name, Developer Mode on, tunnel
   `tunnel_6aa96a85d4508191a9566fe333fae7f6`, Authentication None, Allow all actions. Then
   in the launcher MCP page run Connect harness and Verify runtime. Leave the desktop's
   `Codex Native2` untouched. Confirm afterwards that no new `"tool":"unknown"` lines appear
   in `~/.local/state/tunnel-client/logs/codex-chatgpt-web.log`.
2. Keep devenv on stock releases. Do not re-enable the 5.0.6-task-context wrapper
   (`headless/launcher.before-task-context-20260914`) without recreating the connector
   afterwards, and recreate it again after any release that changes the MCP catalog.
3. Reduce fan-out while ChatGPT rate limits are this tight: prefer sequential subagents on
   ChatGPT Web models; native Codex models are not affected.
4. Optional until the next release ships: return to standard context to remove the 09-16
   payload rejections:

   ```bash
   ~/.codex-chatgpt-web/versions/5.0.8-linux-x64/runtime/bun \
     ~/.codex-chatgpt-web/versions/5.0.8-linux-x64/app/cli.js \
     setup --full --standard-context \
     --tunnel-id tunnel_6aa96a85d4508191a9566fe333fae7f6 \
     --runtime-key-file ~/.codex-chatgpt-web/secrets/tunnel-runtime-automatic.key \
     --browser-host-descriptor ~/.codex-chatgpt-web/runtime/launcher-browser.json \
     --automatic-browser-interaction --restart-service
   ```

5. Update to the release after 5.0.8 when published; it carries the 413 handling and the
   same-turn environment fix (#557) that also shows up here as
   "missing cwd in trusted Codex environment context".

No runtime, connector, tunnel, secret, or Codex configuration was changed during this
investigation.
