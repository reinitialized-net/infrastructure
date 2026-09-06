# Containers Profile

**Module path:** `modules/profiles/containers/`

**Import:** Explicitly pass the profile in a host's module list.

## Overview

The containers profile turns a host into a Docker-backed OCI container host. It is used by `devenv`, `rp1`, `apps1`, `apps2`, `apps3`, and `db1`.

It imports:

- `modules/profiles/meshNetwork`
- `modules/profiles/infraUpdateReport.nix`
- `modules/profiles/secrets.nix`
- `modules/profiles/containers/containerTools.nix`

It assumes `/mnt/data` is available for persistent Docker storage. In this repository that is provided by `modules/profiles/mountData.nix`.

## What It Configures

### Docker

```nix
virtualisation.docker = {
  enable = lib.mkForce true;
  package = pkgs.docker_29;
  daemon.settings = {
    icc = lib.mkForce true;
    no-new-privileges = lib.mkForce true;
  };
  extraOptions = "--default-ulimit nofile=65536:65536";
};

virtualisation.oci-containers.backend = lib.mkForce "docker";
```

For non-container hosts, it also adds:

```nix
boot.kernelParams = [ "systemd.unified_cgroup_hierarchy=1" ];
```

### Docker Storage

Docker data is bind-mounted from the data disk:

```nix
fileSystems."/var/lib/docker/volumes" = {
  device = "/mnt/data/docker/volumes";
  depends = [ "/mnt/data" ];
  fsType = "none";
  options = [ "bind" ];
};

fileSystems."/var/lib/docker" = {
  device = "/mnt/data/docker";
  depends = [ "/mnt/data/docker/volumes" ];
  fsType = "none";
  options = [ "bind" ];
};
```

Import `mountData` on hosts that use this profile:

```nix
modules = [
  "${self}/modules/profiles/containers"
  "${self}/modules/profiles/mountData.nix"
];
```

### Daily Prune

The profile enables Docker auto-prune:

```nix
virtualisation.docker.autoPrune = {
  enable = true;
  dates = "daily";
  flags = [ "--filter" "until=24h" ];
};
```

This removes stopped containers, dangling images, and unused networks older than 24 hours.

## Container Image Auto-Update

The profile defines `services.containerAutoUpdate`.

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `true` | Enables the timer and service |
| `schedule` | `"04:00"` | systemd `OnCalendar` expression |
| `randomizedDelaySec` | `"15min"` | Timer jitter |
| `skipContainers` | `[]` | Container names from `virtualisation.oci-containers.containers` to skip |
| `pullOnly` | `false` | Pull images without restarting containers |
| `restartChangedOnly` | `true` | Restart active containers whose running image differs from the pulled image |

The service iterates through declarative containers, runs `docker pull`, and restarts the matching systemd unit when needed. Unit names come from each container's `serviceName`, defaulting to `docker-<container-name>`.

The comparison uses the running container's image, so a previously pulled image
or a shared tag cannot mask an outstanding update. Inactive services stay stopped;
missing units and failed image inspections fail the update job. `pullOnly` continues
to pull without restarts, and `skipContainers` remains authoritative.

The service logs `container_update_event` lines containing container name, image, service, old image ID, new image ID, and action. Pull failures cause the service to fail after all containers have been checked. It also sets `OnFailure=infra-update-report@%n.service`; with `secrets.infraAutomation` configured, that reporter creates or updates a Forgejo issue through the automatic update tooling.

The profile also attaches the same `OnFailure` reporter to each generated declarative container unit. This covers service crashes and failed restarts, including containers listed in `skipContainers` that are intentionally not restarted by the image pull timer.

Example override:

```nix
services.containerAutoUpdate = {
  schedule = "Mon *-*-* 03:30:00";
  randomizedDelaySec = "30min";
  skipContainers = [ "postgres1" "forgejoRunner" ];
};
```

Useful commands:

```bash
systemctl list-timers docker-container-auto-update.timer
systemctl start docker-container-auto-update.service
journalctl -u docker-container-auto-update.service
```

## Docker User And Volume Migration

The profile creates a system user and group named `docker`:

```nix
users.users.docker = {
  isSystemUser = true;
  shell = pkgs.dash;
  home = "/home/docker";
  createHome = true;
  group = "docker";
  initialHashedPassword = "!";
};
```

The user has a fixed authorized key named `docker-volume-migration`. Its SSH `ForceCommand` parses arguments and allows only the volume migration command forms, legacy SCP server modes, and SFTP. Migration containers use the fixed Alpine image and named volumes; arbitrary Docker commands, host bind mounts, and shell commands are rejected. The login shell does not load writable shell startup files, and forwarding, user SSH startup scripts, and PTYs are disabled.

SCP/SFTP run inside a Bubblewrap sandbox with separate namespaces. Writable host
paths are limited to `/home/docker` and
`/var/lib/docker/volumes/.migration-staging` when present and accessible to the
caller. Existing POSIX permissions still apply; this does not grant traversal
through Docker's private data directory. Only OpenSSH's runtime closure and the
read-only account/group databases accompany those directories. Host `/proc`,
runtime sockets, migration keys and the rest of the Nix store are absent. Symlinks
and protocol-supplied paths resolve inside this view. Sandbox setup failure denies
the transfer. Normal streamed volume migration keeps its existing command path.

The private key for outbound migration is written by `deploy-docker-migration-key` from:

```nix
config.secrets.volumeMigration.file
```

The service atomically writes `/var/lib/docker-volume-migration/identity` with mode `0600` in a root-owned directory. Outbound migration uses an immutable SSH configuration rather than the docker user's writable home configuration. Known host keys are stored in `/var/lib/docker-volume-migration/known_hosts`.

The profile also grants members of the `docker` group passwordless sudo-rs access to run `ssh` and `test` as the `docker` user, plus exact `systemctl stop/start` commands for declared container units. Migration uses those units because NixOS removes declarative containers when they stop. Unmanaged containers still use Docker stop/start; unmanaged containers configured with automatic removal are rejected before stopping.

## `migrate-volumes`

The `migrate-volumes` tool is installed by `containerTools.nix`.

### Modes

| Mode | Required arguments | Purpose |
|------|--------------------|---------|
| `export` | `-v VOLUME` | Create a local backup in the staging directory |
| `import` | `-v VOLUME -f BACKUP_FILE` | Restore a local backup into a Docker volume |
| `transfer` | `-v VOLUME -r HOST` | Stream a volume directly to another host as the `docker` user |

### Options

| Option | Description |
|--------|-------------|
| `-V VOLUME` | Destination volume name when different from source |
| `-c CONTAINER` | Local container to stop/start during export or transfer |
| `-C CONTAINER` | Remote container to stop/start during transfer |
| `-d DIR` | Backup directory, default `/var/lib/docker/volumes/.migration-staging` |
| `-p PORT` | SSH port, default `22` |
| `-n` | Do not stop containers |
| `-k` | Skip checksum verification |
| `-z COMP` | Compression: `gzip`, `bzip2`, `xz`, or `none`; default `gzip` |
| `-h` | Show help |

Examples:

```bash
migrate-volumes export -v postgres1_data -c postgres1
migrate-volumes import -v postgres1_data -f /var/lib/docker/volumes/.migration-staging/postgres1_data.tar.gz
migrate-volumes transfer -v postgres1_data -r 10.1.11.3 -V imported_postgres1_data
```

Transfer mode streams data over SSH and does not leave intermediate backup files on either host.

Backup checksums and archive readability are checked before import stops consumers. Failed discovery or container stops abort the operation. The stop plan includes running OCI containers that depend on a volume consumer, because systemd also stops those dependents. Cleanup resumes only containers that were running before the operation; a failed transfer resumes the source, while a destination that may have been partially written remains stopped. Successful transfers leave the source stopped and resume the destination. Export writes to a temporary file so a failed export preserves the previous backup.

Update both migration hosts to the current tool before using automatic stop/recovery. A destination without the migration planning command is rejected before containers are stopped.

Imports and transfers extract into the selected destination volume. Use a fresh destination volume or take a recoverable snapshot/backup before replacing existing data; interrupted extraction does not automatically roll back volume contents. `-n` explicitly permits copying with running writers and can produce inconsistent data.

Run the offline command-boundary and recovery regression check with:

```bash
python3 modules/profiles/containers/tests/check_migration.py
```

## Mesh Network Integration

Because this profile imports `meshNetwork`, a host can enable mesh networking with:

```nix
services.meshNetwork.enable = true;
```

When Docker is enabled and `services.meshNetwork.dockerIntegration = true`, the mesh module creates the Docker network named `backend`. Declarative containers can attach to it with:

```nix
virtualisation.oci-containers.containers.my-service = {
  image = "nginx:latest";
  networks = [ "backend" ];
};
```

Current host files use the `networks` option rather than Docker `extraOptions = [ "--network=backend" ]`.

Declared containers attached to `backend` start after `docker-meshNetwork.service` creates it. Their units also follow the mesh network service's stop/restart lifecycle.

## Troubleshooting

Check Docker and bind mounts:

```bash
systemctl status docker
mount | grep /var/lib/docker
docker info
docker system df
df -h /mnt/data
```

Check the image update timer:

```bash
systemctl status docker-container-auto-update.timer
journalctl -u docker-container-auto-update.service
```

Check migration key deployment:

```bash
systemctl status deploy-docker-migration-key.service
sudo -u docker test -f /var/lib/docker-volume-migration/identity
```

Check Docker mesh network:

```bash
docker network inspect backend
nft list table inet mesh-docker
```

## See Also

- [Mount Data Profile](mountData.md)
- [Mesh Network Module](meshNetwork.md)
- [Secrets Management](secrets.md)
