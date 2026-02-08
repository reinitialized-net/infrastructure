# Hudu PostgreSQL Connection Error: Host and Port Format

**Date:** February 8, 2026  
**Affected Service:** Hudu (apps1)  
**Symptom:** `PG::ConnectionBad (could not translate host name "10.255.0.11:1024" to address: Name or service not known)`

## Root Cause

The `DB_HOST` environment variable in Hudu's configuration was set to `"10.255.0.11:1024"`, incorrectly combining the database host IP and port into a single value. PostgreSQL client libraries expect the host and port to be provided as separate parameters.

When the PostgreSQL client attempted to resolve "10.255.0.11:1024" as a DNS hostname, it failed because:
1. Colons (`:`) are not valid characters in DNS hostnames
2. The string was being treated as a hostname rather than parsed as host:port
3. The DNS resolver attempted to look up the entire string as a hostname, resulting in "Name or service not known"

## Investigation Steps

1. **Identified the error pattern:** The error message showed PostgreSQL was attempting to resolve "10.255.0.11:1024" as a complete hostname
2. **Examined apps1 secrets configuration:** Found `DB_HOST = "10.255.0.11:1024";` in `/modules/secrets/apps1.nix`
3. **Verified db1 configuration:** Confirmed PostgreSQL is running on db1 at mesh IP `10.255.0.11` with port `1024` exposed
4. **Determined correct format:** Rails/Hudu applications expect separate `DB_HOST` and `DB_PORT` environment variables

## Resolution

Split the database connection parameters in `/modules/secrets/apps1.nix`:

**Before:**
```nix
DB_HOST = "10.255.0.11:1024";
DB_USERNAME = "hudu";
DB_PASSWORD = "SNoAk9yLi5BdV6vPumMEOUKHG6JxkHq3";
DB_NAME = "hudu_production";
```

**After:**
```nix
DB_HOST = "10.255.0.11";
DB_PORT = "1024";
DB_USERNAME = "hudu";
DB_PASSWORD = "SNoAk9yLi5BdV6vPumMEOUKHG6JxkHq3";
DB_NAME = "hudu_production";
```

Deployed the fix using:
```bash
rebuildHost apps1
```

## Lessons Learned

1. **Database connection parameters must follow standard formats:** Most database clients expect host and port as separate configuration values, not combined with a colon separator
2. **Connection string formats vary by tool:** While some tools (like `psql` CLI) accept `host:port` syntax, programmatic clients typically do not
3. **Rails database configuration:** Rails applications using separate environment variables require:
   - `DB_HOST` - Hostname or IP address only
   - `DB_PORT` - Port number as a separate value
   - Alternative: Use `DATABASE_URL` with full connection string format: `postgresql://user:pass@host:port/database`

## Related Configuration

- **db1 PostgreSQL service:** Running on mesh IP `10.255.0.11:1024` (container port 5432 mapped to mesh port 1024)
- **apps1 Hudu containers:** `hudu1` and `hudu2` both connect to the same database using shared environment variables
- **Mesh network topology:** db1 has nodeId 11, resulting in mesh IP `10.255.0.11`

## Prevention

When configuring database connections for Rails/Ruby applications:
- Always use separate `DB_HOST` and `DB_PORT` variables when using the ENV-based configuration
- Alternatively, use `DATABASE_URL` with proper connection string format: `postgresql://user:pass@host:port/database`
- Test database connectivity after migration with a simple connection test before deploying the full application
