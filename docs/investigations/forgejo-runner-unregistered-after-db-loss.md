# Forgejo Runner: Unregistered Runner Error after PostgreSQL Data Loss

## Symptoms

The `forgejoRunner` container on `apps2` would start but immediately exit with the following error in the logs:

```
time="2026-03-01T20:33:48Z" level=error msg="fail to invoke Declare" error="unauthenticated: unregistered runner"
Error: unauthenticated: unregistered runner
```

The container entered a fast collapse/restart loop.

## Root Cause

The issue was a mismatch between the runner's local registration state (`.runner` file) and the Forgejo instance's database.

1. **Previous Registration:** The runner was initially registered on 2026-02-08. This created a `.runner` file in the persistent volume containing a `uuid` and `token`.
2. **Database Data Loss:** A critical data loss incident occurred on the PostgreSQL server (`db1`) on 2026-02-10 (recorded in `docs/investigations/postgresql-18-volume-mount-data-loss.md`). This wiped the `action_runner` table in Forgejo's database.
3. **Stale Local State:** When the `forgejoRunner` container restarted, it found the existing `.runner` file and skipped the registration step. However, the Forgejo instance no longer recognized that `uuid`/`token` combination because its database records were gone.
4. **Script Limitation:** The startup script in `hosts/apps2.nix` only attempted registration if `/data/.runner` was missing. It did not handle cases where the file existed but was no longer valid.

## Investigation Steps

1. **Log Analysis:** Checked logs on `apps2` using `journalctl -u docker-forgejoRunner` which revealed the `unregistered runner` error.
2. **State Verification:** Verified the presence of `/data/.runner` on `apps2` and noted its creation date (Feb 8).
3. **Database Check:** Queried the Forgejo database on `db1`:
   ```sql
   SELECT id, uuid, name, token_hash FROM action_runner;
   ```
   Result: `0 rows`. This confirmed that the Forgejo instance had no record of any registered runners.
4. **Token Check:** Noticed that active registration tokens existed in `action_runner_token`, indicating a fresh start for the Actions system post-data-loss.

## Fix Applied

### 1. Manual Cleanup (Immediate Fix)
Manually deleted the stale `.runner` file on `apps2` to trigger a one-time re-registration:
```bash
ssh rnetadmin@10.1.11.3 "sudo rm /mnt/data/docker/volumes/forgejoRunner_data/_data/.runner"
```

### 2. Startup Script Resilience (Structural Fix)
Updated `hosts/apps2.nix` to make the startup script more resilient. The script now:
- Encapsulates registration logic in a function.
- Attempts to start the daemon.
- If the daemon fails (which happens on authentication errors), it assumes the local state is stale, deletes `.runner`, and attempts re-registration automatically.

```bash
# Modified startup logic
if ! forgejo-runner daemon --config /data/config.yml; then
  echo "Runner daemon exited with failure. Checking for registration issues..."
  rm -f /data/.runner
  if register_runner; then
    exec forgejo-runner daemon --config /data/config.yml
  fi
fi
```

## Prevention

1. **Automatic Re-registration:** Startup scripts for non-interactive runners should include logic to detect "unregistered" or "unauthenticated" errors and attempt a clean re-registration.
2. **State/Database Synchronization:** Always remember that for services like Forgejo Actions, the state is split between the runner (file) and the server (database). Wiping one requires resetting the other.

---

## Follow-up: Duplicate Runner Entries (2026-03-05)

### Symptoms

After manually deleting `/data/.runner` to force a label update (adding the `nix-latest` label), the runner re-registered as a **new** runner (ID 2), while the old runner (ID 1) remained active in Forgejo, producing duplicate entries both showing "Idle".

### Root Cause

The re-registration path (both via manual `.runner` deletion and via the daemon-failure fallback) only removed the **local** `.runner` file. It did not call the Forgejo API to remove the old runner from the **server-side** database, so Forgejo kept both entries alive.

### Fix Applied

Three changes were made to `hosts/apps2.nix`:

1. **`deregister_runner` function** — Before removing `.runner`, the script now extracts the runner ID from the file (`grep -o '"id":[0-9]*'`) and calls `DELETE /api/v1/admin/runners/{id}` using a Forgejo admin API token. Both the `.runner` file and the `.runner-labels` tracking file are then removed. The function degrades gracefully if the admin token is unconfigured or if `curl` is unavailable.

2. **Label-change detection** — On every startup, the script compares `CONFIGURED_LABELS` (from the Nix-evaluated secret) against the labels stored in `/data/.runner-labels` at the time of last registration. If they differ and a `.runner` file exists, it proactively calls `deregister_runner` before creating a new registration. This means future label updates in the Nix config are automatically handled on the next container restart — no manual file deletion required.

3. **`FORGEJO_ADMIN_API_TOKEN` secret** — A new key was added to `secrets.forgejoRunner` in `modules/secrets/apps2.nix` (and the example). This must be a token for a Forgejo admin user, generated at: *Forgejo → Settings → Applications → API Tokens*.

### How Label Updates Work Going Forward

1. Update `FORGEJO_RUNNER_LABELS` in `modules/secrets/apps2.nix`.
2. Run `rebuildHost apps2` to deploy the updated Nix config.
3. Restart the container (`sudo docker restart forgejoRunner` on apps2), or wait for the next automatic restart.
4. The startup script detects the label change, deregisters the old runner, and registers a new one — Forgejo will show only one runner with the updated labels.
