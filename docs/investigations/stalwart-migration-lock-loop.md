# Stalwart Mail Server Migration Lock Loop

**Date**: 2026-02-07
**Host**: apps1 (stalwartOne Docker container)
**Database**: PostgreSQL on apps3 (postgres1 container)
**Stalwart Version**: v0.15.4

## Symptoms

After restarting the `stalwartOne` Docker container on apps1, mail.reinitialized.net became inaccessible with the browser error:

> "The page you are trying to view cannot be shown because the authenticity of the received data could not be verified"

Investigation revealed:
- SSL cert on rp1 was valid (Let's Encrypt, not expired)
- SSL handshake completed successfully
- stalwartOne returned empty reply and closed connection
- Port 8080 in the container showed connection refused
- No listening ports existed in the container's network namespace

## Root Cause

The stalwart process was stuck in an infinite startup loop, never reaching the point where it opens listener ports.

### Chain of Events

1. **Missing schema version**: The `p` table (SUBSPACE_PROPERTY) in PostgreSQL had no row at key `0x00`, which should store the database schema version (`5` for v0.15.4).

2. **Migration misidentification**: Without a schema version, stalwart's `try_migrate()` function in `crates/migration/src/lib.rs` enters the `None` branch, which checks `is_new_install()`. Since the database contains data (32 directory entries, 3559 settings), it's not a new install, so stalwart attempts `migrate_v0_11()` — a migration designed for pre-v0.12 database schemas.

3. **v0.11 migration failure**: The v0.11 migration code references table structures and subspaces that don't exist in the v0.15.4 schema, resulting in PostgreSQL error `42P01` (undefined_table) at `principal_v1.rs:35`.

4. **Race condition on restart**: Docker started two stalwart processes nearly simultaneously (05:41:15 and 05:41:19). The first acquired the migration lock (`KV_LOCK_HOUSEKEEPER` prefix byte `0x18` + `migrate_core_lock` key, stored in the `m` table); the second was blocked waiting for the lock.

5. **Crash cycle**: The process holding the lock ran for ~5 minutes (lock TTL = 300 seconds), hit the `42P01` error, and crashed without releasing the lock. Docker's restart policy spawned a new process, which either waited for the lock to expire or immediately tried and failed again. This created an endless cycle:
   - Acquire lock → attempt v0.11 migration → hit 42P01 → crash
   - New process waits ~5 minutes for lock expiry → repeat

### Why the Schema Version Was Missing

The `p` table was completely empty (0 rows). The schema version is normally written during the first successful migration or initial setup. The most likely cause is:
- A previous upgrade or migration that failed partway through, before writing the version marker
- A database restore that didn't include the property table data
- The row was accidentally deleted during a maintenance operation

## How the Migration Lock Works

Stalwart uses a distributed lock stored in the in-memory store (PostgreSQL `m` table for this deployment):

| Component | Value |
|-----------|-------|
| Table | `m` (SUBSPACE_IN_MEMORY_VALUE = `0x6d`) |
| Key | `0x18` (KV_LOCK_HOUSEKEEPER = 24) + `migrate_core_lock` |
| Value | u64 big-endian expiry timestamp |
| TTL | 300 seconds (5 minutes) |
| Retry interval | 30 seconds |

The `try_lock()` function performs an atomic compare-and-swap:
1. Read current lock expiry timestamp
2. If lock exists and hasn't expired, return false (lock busy)
3. Assert old value, write new expiry = `now() + 300`
4. On success, lock is acquired; on assertion failure (race), return false

The lock is released via `remove_lock()` which deletes the key. If the process crashes, the lock remains until its TTL expires.

## Resolution

### Steps Taken

1. **Stopped the container** to end the crash cycle:
   ```bash
   docker stop stalwartOne
   ```

2. **Inserted the correct schema version** into the property table:
   ```sql
   INSERT INTO p (k, v) VALUES (decode('00', 'hex'), decode('00000005', 'hex'));
   ```
   The value `0x00000005` is `5u32` in big-endian (DATABASE_SCHEMA_VERSION for v0.15.4).

3. **Cleaned up the stale migration lock**:
   ```sql
   DELETE FROM m WHERE encode(k, 'escape') LIKE '%migrate%';
   ```

4. **Started the container**:
   ```bash
   docker start stalwartOne
   ```

5. **Verified** stalwart started successfully with all ports listening (25, 110, 143, 443, 465, 587, 993, 995, 4190, 8080) and mail.reinitialized.net returned HTTP 200 with valid SSL.

### Schema Version Reference

| Version | Stalwart Release |
|---------|-----------------|
| 1 | v0.12.0 |
| 2 | v0.12.4 |
| 3 | v0.13.0 |
| 4 | v0.14.0 |
| 5 | v0.15.0+ |

## Prevention

- **Database backups**: Ensure PostgreSQL backups include all tables, especially the `p` (property) table which contains critical schema metadata.
- **Schema version monitoring**: After stalwart upgrades, verify the schema version exists:
  ```sql
  SELECT encode(k, 'hex') as key, encode(v, 'hex') as value FROM p WHERE k = decode('00', 'hex');
  ```
  Expected result: `key=00, value=00000005` for v0.15.4.
- **Startup health checks**: Monitor stalwart logs for "Migration lock busy" messages, which indicate a migration is in progress or stuck.
- **Single-instance restarts**: Avoid configurations where multiple stalwart instances can start simultaneously against the same database, as this can create race conditions with the migration lock.
