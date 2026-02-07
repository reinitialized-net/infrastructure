# Stalwart IMAP Authentication Failure — Store Mismatch

**Date:** 2025-07-15
**Affected Service:** Stalwart Mail Server (stalwartOne container on apps1)
**Severity:** Critical — All IMAP/SMTP authentication broken
**Related:** [stalwart-migration-lock-loop.md](stalwart-migration-lock-loop.md) (preceded this issue)

## Symptoms

After restarting the stalwartOne Docker container (which triggered the migration lock loop documented separately), IMAP authentication failed for **all accounts** with `A002 NO [AUTHENTICATIONFAILED] Authentication failed`, despite using correct credentials.

Key observations:
- Web admin interface (HTTP API) worked fine with fallback-admin credentials
- IMAP auth failed for every account, including freshly created ones
- Setting a known plaintext password via the management API and immediately testing IMAP with that exact password still failed
- No IPs were blocked by fail2ban
- No configuration overrides in the database settings table
- RocksDB was not corrupted (clean startup in LOG file)

## Root Cause

**A store mismatch between the management API and the authentication directory.**

Stalwart v0.15.4 has two separate code paths that access principal (user/account) data:

| Operation | Code Path | Store Used |
|-----------|-----------|------------|
| **Create account** (POST /api/principal) | `self.core.storage.data.create_principal()` | `storage.data` |
| **Update password** (PATCH /api/principal) | `self.core.storage.data.update_principal()` | `storage.data` |
| **List/Get accounts** (GET /api/principal) | `self.store().query()` → `self.core.storage.data` | `storage.data` |
| **Authenticate** (IMAP/SMTP/JMAP) | `directory.query()` → `DirectoryInner::Internal(store)` | `directory.internal.store` |

The configuration had:

```toml
[storage]
data = "default"  # PostgreSQL on apps3

[directory.internal]
type = "internal"
store = "rocksdb"  # Local RocksDB at /opt/stalwart/data
```

This meant:
- The management API created users and set passwords in **PostgreSQL**
- Authentication looked for users in **RocksDB**
- These are completely separate databases with no synchronization

When a user was created or a password was changed via the web admin/API, the data went to PostgreSQL. When IMAP tried to authenticate, it queried RocksDB — where the user didn't exist — and returned "user not found", which stalwart reported as `auth.failed`.

### Why This Wasn't Obvious

1. **The management API worked perfectly** — creating, listing, and updating accounts all succeeded because they operated on PostgreSQL
2. **Passwords appeared correct** when queried via GET `/api/principal/{name}` because that also reads from PostgreSQL
3. **RocksDB appeared healthy** — no corruption errors, clean startup
4. **Trace logs were misleading** — the directory lookup failure doesn't generate a `store.data-read` trace event when the internal directory uses a different store from `storage.data`. The only visible trace events were two `store.data-write` operations (fail2ban rate limit counter increments) and then `auth.failed`
5. **The `d` table in PostgreSQL contained directory data** (40 rows including user mappings), making it appear that all directory data was in PostgreSQL

### Source Code Evidence

Key code paths in the Stalwart codebase (`stalwartlabs/stalwart`):

- `Server::store()` in `crates/common/src/core.rs` returns `&self.core.storage.data` (PostgreSQL)
- `Server::directory()` returns `&self.core.storage.directory` which wraps `DirectoryInner::Internal(store)` where `store` comes from `directory.<name>.store` config (RocksDB)
- Management API operations (`crates/jmap/src/api/management/principal.rs`) call methods on `self.core.storage.data`
- Authentication flow (`crates/common/src/auth/mod.rs`) calls `directory.query()` which dispatches to the directory's internal store
- The two `store.data-write` trace events are from `is_rate_allowed()` in `crates/store/src/dispatch/lookup.rs` — fail2ban rate limit counters incremented once for the IP and once for the username

## Investigation Steps

1. **Confirmed auth fails for all accounts** on IMAP (both proxied through rp1 and direct to container)
2. **Confirmed web admin HTTP auth works** via fallback-admin mechanism
3. **Ruled out proxy/TLS issues** by testing direct connection to container IP 172.20.0.3:993
4. **Identified directory uses RocksDB** via config: `directory.internal.store = "rocksdb"`
5. **Verified RocksDB not corrupted** via LOG file
6. **Checked for blocked IPs** — none found
7. **Changed fallback-admin to known password** "AdminTest456!" to enable API testing
8. **Confirmed user data exists** via API: admin@reinitialized.net (id=5), noreply (id=6), test (id=7)
9. **Set known plaintext password** "TestPw999" via API PATCH — confirmed stored via GET
10. **Proved auth still fails** with known password — eliminated password mismatch as cause
11. **Reviewed full config.toml** — no IMAP-specific auth settings, no cache, no overrides
12. **Checked PostgreSQL settings table** for config overrides — only `oauth.key` found
13. **Analyzed trace logs** — found 2x `store.data-write` (fail2ban counters) but no directory read
14. **Researched Stalwart source code** — discovered `self.store()` (management API) and `directory.query()` (auth) use different store instances
15. **Confirmed the store mismatch** — management API writes to `storage.data` (PostgreSQL), authentication reads from `directory.internal.store` (RocksDB)

## Fix Applied

Changed `directory.internal.store` in `/opt/stalwart/etc/config.toml` from `"rocksdb"` to `"default"`:

```toml
# Before (broken):
directory.internal.store = "rocksdb"

# After (fixed):
directory.internal.store = "default"
```

Then restarted the stalwartOne container. IMAP authentication immediately worked.

## Temporary Changes Made During Investigation

⚠️ **These should be reverted:**

1. **Fallback admin password** was changed from the original hash to the sha512 hash of "AdminTest456!" — update to the real admin password
2. **admin@reinitialized.net password** was set to plaintext "TestPw999" via the management API — change to the real password
3. **Trace logging** was enabled (`tracer.log.level = "trace"`) — consider reverting to a less verbose level for production

## Lessons Learned

1. **Stalwart's internal directory must use the same store as `storage.data`** when using the `internal` directory type. The management API always operates on `storage.data`, so the directory's store must match.
2. **The absence of trace events can be as informative as their presence** — the missing `store.data-read` for directory lookups was a key clue that the directory was querying a different store.
3. **When using a two-store architecture** (e.g., PostgreSQL for data + RocksDB for caching), be careful which components point to which store. The `storage.data` and `directory.internal.store` settings must be coordinated.
4. **This issue likely pre-existed** but went unnoticed if original accounts were created before the store split, or if authentication happened to work through a different mechanism (e.g., if accounts were originally in RocksDB and then migrated to PostgreSQL without updating the directory config).
