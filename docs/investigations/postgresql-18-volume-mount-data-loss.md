# PostgreSQL 18 Volume Mount Data Loss

## Date
2026-02-10

## Severity
**CRITICAL** - Data loss occurred

## Summary
PostgreSQL database on db1 experienced data loss due to incorrect volume mount configuration when using PostgreSQL 18. The volume was mounted at the PostgreSQL 17-style path (`/var/lib/postgresql/data`), causing Docker to create an anonymous, non-persistent volume at the actual data location (`/var/lib/postgresql`).

## Root Cause

PostgreSQL 18 introduced a **breaking change** in how volumes should be mounted compared to PostgreSQL 17 and earlier versions.

### PostgreSQL 17 and Below
- **PGDATA location:** `/var/lib/postgresql/data`
- **Dockerfile VOLUME:** `/var/lib/postgresql/data`
- **Required mount point:** `/var/lib/postgresql/data`
- **Behavior:** Mounting at `/var/lib/postgresql/data` correctly persists the database

### PostgreSQL 18 and Above
- **PGDATA location:** `/var/lib/postgresql/18/docker` (version-specific)
- **Dockerfile VOLUME:** `/var/lib/postgresql` (parent directory)
- **Required mount point:** `/var/lib/postgresql`
- **Behavior:** If you mount at `/var/lib/postgresql/data`, Docker creates an anonymous volume at `/var/lib/postgresql` which is **NOT persistent**

## Evidence

### Container Inspection
```bash
$ sudo docker inspect postgres1 | grep -A 5 'PGDATA'
"PGDATA=/var/lib/postgresql/18/docker"
```

### Mount Configuration (Before Fix)
```bash
$ sudo docker inspect postgres1 | grep -A 20 'Mounts'
"Mounts": [
    {
        "Type": "volume",
        "Name": "postgres1_data",
        "Source": "/var/lib/docker/volumes/postgres1_data/_data",
        "Destination": "/var/lib/postgresql/data",  # Named volume (old style)
        ...
    },
    {
        "Type": "volume",
        "Name": "221c928e0b6bd734d59d09154604719f042f4cfb128e73bc1af29a649008373d",
        "Source": "/var/lib/docker/volumes/221c928e0b6bd734d59d09154604719f042f4cfb128e73bc1af29a649008373d/_data",
        "Destination": "/var/lib/postgresql",  # ANONYMOUS VOLUME (actual database location)
        ...
    }
]
```

The anonymous volume at `/var/lib/postgresql` is where the actual database data was stored, but this volume is not persistent across container recreations.

## The Fix

### Configuration Change
Changed the volume mount point in [hosts/db1.nix](../../hosts/db1.nix):

**Before (Incorrect for PostgreSQL 18):**
```nix
volumes = [
  "postgres1_data:/var/lib/postgresql/data"
];
```

**After (Correct for PostgreSQL 18):**
```nix
volumes = [
  # PostgreSQL 18+ requires mounting at /var/lib/postgresql (not /data subdirectory)
  # This is a breaking change from PostgreSQL 17 and below
  # See: https://hub.docker.com/_/postgres (PGDATA section)
  "postgres1_data:/var/lib/postgresql"
];
```

### Deployment
1. Update the configuration in db1.nix
2. Rebuild the NixOS configuration:
   ```bash
   rebuildHost db1
   ```
3. The PostgreSQL container will be recreated with the correct mount point
4. **Note:** Existing data in the old anonymous volume will be lost (already lost due to container recreation)
5. Restore from backup

## Prevention

### Version-Specific Configuration
When using PostgreSQL in Docker, always check the version-specific volume mount requirements:

- **PostgreSQL ≤17:** Mount at `/var/lib/postgresql/data`
- **PostgreSQL ≥18:** Mount at `/var/lib/postgresql`

### Alternative: Explicit PGDATA Override
If you need to maintain the old path structure for PostgreSQL 18+, you can override PGDATA:

```nix
environment = {
  PGDATA = "/var/lib/postgresql/data";  # Override default
  # ... other env vars
};
volumes = [
  "postgres1_data:/var/lib/postgresql/data"
];
```

However, this approach is **not recommended** as it goes against the PostgreSQL 18 design and may cause issues with future upgrades.

### Testing Before Production
Always test PostgreSQL major version upgrades in a development environment:

1. Deploy to a test system first
2. Verify volume mounts with `docker inspect <container>`
3. Check for anonymous volumes (indicates misconfiguration)
4. Perform a container recreation to ensure data persists

## Related Documentation

- [PostgreSQL Official Docker Image Documentation](https://hub.docker.com/_/postgres)
- [PostgreSQL 18 PGDATA Changes](https://github.com/docker-library/postgres/pull/1259)
- [Understanding Docker Volumes](https://docs.docker.com/storage/volumes/)

## Lessons Learned

1. **Breaking changes in upstream containers** can cause silent data loss if not properly tested
2. **Always inspect container mounts** after deployment to verify configuration
3. **Version-specific documentation** must be consulted when upgrading major versions
4. **Anonymous volumes** are a red flag that indicates misconfiguration
5. **Regular backups** are essential - they prevented total data loss in this incident

## Checklist for PostgreSQL Version Upgrades

- [ ] Review upstream changelog for breaking changes
- [ ] Check volume mount requirements for the target version
- [ ] Deploy to test environment first
- [ ] Verify configuration with `docker inspect`
- [ ] Check for anonymous volumes (should be NONE)
- [ ] Test container recreation (stop/start)
- [ ] Verify data persistence after recreation
- [ ] Take full backup before production deployment
- [ ] Document any configuration changes required
