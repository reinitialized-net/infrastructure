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
