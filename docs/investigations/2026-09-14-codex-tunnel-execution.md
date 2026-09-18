# Codex tunnel execution investigation

Investigated on devenv, 2026-09-14. Local context and diagnostic improvements
are installed; reliable browser execution remains unresolved.

## Confirmed working

- Codex Web GPT 5.0.6 runs in full mode; its Responses endpoint and turn broker
  accept work. The local CLI is Codex 0.154.0.
- Installed tunnel-client is 0.0.12, revision
  `881c9a8fed7cccbe6607cd419863bbca506b8215`.
- The running tunnel's `/healthz` and `/readyz` return `live` and `ready`.
- Its configured MCP command uses the installed bridge and the same
  `~/.codex-chatgpt-web/runtime/turn-broker.sock` as the Responses server.
- A temporary diagnostic owner registered a fresh, five-minute capability with
  the running broker. An actual Codex Native2 connector call reached that broker,
  executed the strictly matched `printf TUNNEL_DIRECT_OK` command in a temporary
  workspace, and returned `TUNNEL_DIRECT_OK`, exit code 0. The owner then revoked
  the capability and removed its private token file.
- Repeating that connector call after revocation correctly returned
  `INVALID_ARGUMENT` with "turn token is invalid, expired, or revoked" and did
  not execute the command. Capability refusal behavior remains intact.

## Browser failure and attempted repair

The original failed task registered a capability under trace `8706a7f5a853`.
Its two inventory calls were accepted with the matching token fingerprint.
No executable call from that task appears in the local tunnel or broker logs.
Consequently, the screenshot's expired-token message does not establish that
the active local capability was expired, or that the tunnel API key was invalid.

A new Codex CLI task through the running ChatGPT browser reproduced the failure
with the harmless command `printf TUNNEL_EXEC_OK`. The browser submitted the
same capability value as its transport prompt, but no execution request reached
the local tunnel. The browser reported an invalid/expired/revoked token.

Refreshed the existing Codex Native2 connector using its ChatGPT Settings Refresh
action. Its existing permission selection was already Allow all actions. No
credentials or permission settings were changed.

A second fresh task after the refresh attempted `printf TUNNEL_REFRESH_OK`.
The browser's final result instead reported: "The local command was blocked by
the automatic safety check, so there was no actual shell output to report."
Again, no command reached the local tunnel. This is the browser model's reported
reason; an independent structured rejection with a more specific reason was not
available. Do not treat the connector refresh as an end-to-end repair.

## Correlation identifiers

| Test | Codex thread | Browser request |
| --- | --- | --- |
| Before refresh | `01a0a163-7db0-7c31-ae2a-949a331c9f92` | `40cb933d-7987-4664-9eb8-71d3641bffb2` |
| After refresh | `01a0a169-5700-7f22-9bbe-8a9488445888` | `ccf9435b-e887-4c0c-9f13-85a048a29225` |

Local evidence:

- Launcher: `~/.config/Codex Web GPT/logs/launcher.jsonl`
- Tunnel: `~/.local/state/tunnel-client/logs/codex-chatgpt-web.log`
- Before-refresh test: `/tmp/codex-tunnel-smoke.jsonl`
- After-refresh test: `/tmp/codex-tunnel-refresh.jsonl`

The remaining failure is upstream of the local tunnel in the browser connector
execution path. These request IDs and the contrasting direct-connector success
are the useful evidence for support or an upstream bridge investigation. A
working health endpoint alone is not sufficient validation; closure requires an
actual command result returned to a fresh browser-backed Codex task.

During the initial investigation, no fleet deployment, Nix configuration change,
package reinstall, token rotation, or tunnel restart was performed. Existing
unrelated source edits in the separate codex-chatgpt-web checkout were preserved.

OpenAI's [Secure MCP Tunnel documentation](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels)
describes the control-plane/runtime-key and private MCP forwarding layers.

## Follow-up: safety-review and revocation reports

The user's later failure corresponds to native thread
`01a0a13a-5a46-74b0-9f57-4c885a001abe`, browser trace `b17bbdf49fcd`.
Two repository inspection commands completed successfully at 19:47:32 and
19:47:39 UTC. The subsequent reported rejection did not reach the local tunnel.
The broker committed browser completion at 19:48:42 UTC. There is no evidence
that it prematurely revoked this task. Local Codex used its existing `never`
approval policy and `danger-full-access` sandbox configuration.

OpenAI's [recommended configuration documentation](https://learn.chatgpt.com/docs/cyber-safety/recommended-configuration#review-sensitive-codex-actions)
describes contextual review of sensitive Codex actions. Local permissions and
an installed tunnel key do not establish that every browser-side action will
be approved. Neither approval settings nor cancellation enforcement were changed.

### Installed improvements

Changes are in the separate, initially clean installed-source checkout at
`/home/develop/.local/share/codex-chatgpt-web/source`, based on release commit
`e85e369`. The user's existing changes under
`/home/develop/projects/codex-chatgpt-web` were preserved.
The changes are committed locally as `c31c2bb` and exported to
`~/.local/share/codex-chatgpt-web/task-context-and-status.patch`. Nothing was pushed.

- Browser prompts now expose an exact, readable copy of the canonical current
  instruction and validated working directory, workspace roots, and sandbox
  policy above the full original context. Oversized instructions are not
  truncated. Repository content, tool output, and historical assistant messages
  cannot supply this header. It grants no additional authority.
- A read-only `codex_turn_status` MCP action distinguishes an active local
  capability from a retired or unavailable one. It does not run a command,
  renew a deadline, claim a binding, activate a manual task, or reopen a task.
- Retirement logs record the task trace, pending-call count, and completion
  state without logging the capability. Existing rejection, cancellation,
  timeout, and expiry behavior is retained.

The built runtime passed manifest validation and the relocatable release smoke
test. Its installed bundle ID is
`8893843bd16e7fe0059de28ee43edcb9dd1220024af8dd34160d92a4811c1a20`.
The launcher was restarted only after both active-turn counters were zero.
The Responses service and tunnel returned healthy/ready afterwards.

The original AppImage is retained. The active wrapper
`~/.local/share/codex-chatgpt-web/headless/launcher` launches the isolated AppDir
at `~/.local/lib/codex-web-gpt/5.0.6-task-context/AppDir`. Its original script is
saved beside it as `launcher.before-task-context-20260914`. Restoring that script
and restarting the idle launcher returns to the original validated runtime.
An upstream launcher update may replace this local override; this is not an
upstream release.

The existing Codex Native2 connector was refreshed through ChatGPT Settings.
Both the refresh response and subsequent actions response contained
`codex_turn_status`, with HTTP 200 and an "Actions refreshed" notification.
The existing Allow all actions selection and credentials were preserved.
This verifies catalog refresh, not availability of the new tool to every
browser model session.

### Validation and remaining boundary

- TypeScript checking and `git diff --check` passed.
- The focused context, prompt, native MCP, and Zero Risk lifecycle suite passed:
  116 tests, including preserved denied results, unchanged expiry, cancellation,
  and refusal of retired capabilities.
- The full suite produced 994 passes, one platform skip, and two large-prompt
  timeouts. Both timeout failures reproduced on the unmodified release. In an
  isolated checkout with only their time limits extended, both passed with all
  original assertions unchanged. No test deadline was changed in the patch.
- The installed MCP implementation returned `active` and then `retired` for a
  diagnostic capability before and after explicit owner retirement.

A fresh browser-backed CLI task used a temporary workspace with a fixture and
instructions for reading, editing, process polling, and an intentional exit 7.
Its canonical instruction and validated workspace were confirmed in the actual
browser prompt. The thread was `01a0a194-0fe6-78b2-87cf-b2dfffd59813`, browser
trace `b7c83627bc07`.

`cat fixture.txt` reached the outer Codex harness at 20:21:03 UTC and returned
`TUNNEL_BROWSER_FIXTURE_OK`, exit 0. The browser then reported an invalid,
expired, or revoked token while trying to discover/inspect task status. No
follow-up invocation reached the tunnel. The broker retained the capability
until browser completion at 20:21:15.159 UTC and retired it at
20:21:15.228 UTC with `pending=0 completed=true`.

The edit, process polling, and post-failure browser checks were not reached in
this first probe, which did not create `checked.txt`. The browser's final prose is not independent
evidence of the upstream rejection mechanism. Its reported revocation is
inconsistent with the observed local capability lifetime. Do not represent
these local improvements as a complete repair of browser execution, or rotate
the working tunnel credentials based on this report.

An independent probe then exercised the previously unexecuted edit workflow,
without retrying the failed discovery request. Thread
`01a0a19b-a07e-7e81-ba07-4178df84eae2`, trace `1d0de64b90fd`, successfully
performed `apply_patch` at 20:29:11 UTC. Independent local byte verification
confirmed that `checked.txt` contains exactly `TUNNEL_BROWSER_EDIT_OK\n`.
The subsequent browser request to read that file again reported an invalid,
expired, or revoked token and never reached the tunnel. The broker retired this
task only after browser completion at 20:29:25.881 UTC, with
`pending=0 completed=true`. The browser also reported that `codex_turn_status`
was not directly available to its model session, despite the successful server
catalog refresh. Process polling and post-failure browser execution remain
unverified. This reproduces failure of follow-up calls after both a successful
command and a successful edit; it does not demonstrate premature local expiry.

Additional local evidence:

- `/tmp/codex-tunnel-task-context-live.jsonl`
- `/tmp/codex-tunnel-edit-poll-live.jsonl`
- `/tmp/codex-tunnel-focused-final.log`
- `/tmp/codex-tunnel-all-tests.log`
- `/tmp/codex-tunnel-baseline-tests.log`
- `/tmp/codex-tunnel-timeout-diagnostic.log`
- `/tmp/codex-tunnel-typecheck-final.log`
- `/tmp/codex-tunnel-bundle-smoke.log`

No production camera, recording, detector, fleet configuration, or secrets were
changed. The remaining browser execution boundary requires upstream diagnosis;
no rejected action was automatically replayed and no revoked capability was
resurrected.
