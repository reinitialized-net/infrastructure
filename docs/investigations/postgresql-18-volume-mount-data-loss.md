# PostgreSQL 18 Volume Mount Data Loss

## Date
2026-02-10

## Severity
**CRITICAL** - Data loss occurred

## Summary
PostgreSQL database on db1 experienced data loss due to incorrect volume mount configuration when using PostgreSQL 18. The named volume was mounted at the PostgreSQL 17-style path (`/var/lib/postgresql/data`), while the actual data was written to an anonymous volume at `/var/lib/postgresql`.

This is a historical incident. An anonymous volume may still contain recoverable data; recreation does not prove it has been deleted. Preserve candidate volumes and backups before stopping, recreating, remounting, or pruning containers. NixOS's declarative container removal can also remove attached anonymous volumes.

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
- **Behavior in this incident:** The child mount left the actual data in an anonymous parent volume that was not explicitly reattached by the declarative configuration

## Evidence

### Container Inspection
```bash
$ sudo docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' postgres1 | sed -n '/^PGDATA=/p'
"PGDATA=/var/lib/postgresql/18/docker"
```

### Mount Configuration (Before Fix)
```bash
$ sudo docker inspect --format '{{json .Mounts}}' postgres1 | jq
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

The anonymous volume at `/var/lib/postgresql` held the actual database. A replacement container can select a new anonymous volume, leaving the earlier data disconnected or removing it during cleanup. Inspect and preserve existing volumes before deciding recovery is impossible.

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

### Preconditions For A Similar Recovery

1. Identify the running image version, effective `PGDATA`, mount destinations, and every candidate data volume. Print only the needed inspection fields; a full environment dump can expose database credentials.
2. Before stopping or recreating the container, preserve recoverable database backups and snapshots of candidate volumes. Test restoration. If PostgreSQL cannot start, preserve the existing files for recovery instead of initializing a new cluster over them.
3. Schedule maintenance, quiesce application writers, and prevent scheduled updates from racing the recovery. Use the declared `docker-postgres1.service` lifecycle rather than `docker stop`/`docker start`; account for automatic container and anonymous-volume removal before stopping it.
4. Plan how the existing cluster will populate the intended named volume and version-specific directory. Changing a mount or `PGDATA` does not migrate data or upgrade a PostgreSQL major version. Test the recovery or upgrade against a restored copy using compatible PostgreSQL tools first.
5. Validate the proposed NixOS configuration without activation:
   ```bash
   nix build path:.#nixosConfigurations.db1.config.system.build.toplevel
   ```
6. Once recovery and rollback are ready, activate the reviewed configuration from `devenv` with `rebuildHost db1`. Verify the effective mounts, database contents, and application connectivity. Retain the original volumes and backups until recovery has been accepted; do not prune them during validation.

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

This does not move existing files or perform a major-version upgrade. Do not apply it as an incident shortcut. The current host uses the parent mount; any alternate layout needs the same backup, compatibility, and restored-copy tests described above.

### Testing Before Production
Always test PostgreSQL major version upgrades in a development environment:

1. Deploy to a test system first
2. Verify volume mounts with `docker inspect <container>`
3. Confirm the effective database directory is in the intended named volume
4. Perform a container recreation on the test system to ensure restored data persists; do not recreate production merely as a test

## Related Documentation

- [PostgreSQL Official Docker Image Documentation](https://hub.docker.com/_/postgres)
- [PostgreSQL 18 PGDATA Changes](https://github.com/docker-library/postgres/pull/1259)
- [Understanding Docker Volumes](https://docs.docker.com/storage/volumes/)

## Lessons Learned

1. **Breaking changes in upstream containers** can cause silent data loss if not properly tested
2. **Always inspect container mounts** after deployment to verify configuration
3. **Version-specific documentation** must be consulted when upgrading major versions
4. **Unexpected anonymous database volumes** require investigation and preservation before cleanup
5. **Regular backups** are essential - they prevented total data loss in this incident

## Checklist for PostgreSQL Version Upgrades

- [ ] Review upstream changelog for breaking changes
- [ ] Check volume mount requirements for the target version
- [ ] Deploy to test environment first
- [ ] Verify configuration with `docker inspect`
- [ ] Identify and preserve any unexpected anonymous database volumes
- [ ] Test container recreation on a restored copy using the declared service lifecycle
- [ ] Verify data persistence after recreation
- [ ] Take and verify a restorable backup before stopping or changing production
- [ ] Document any configuration changes required
