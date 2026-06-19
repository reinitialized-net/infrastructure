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
| `restartChangedOnly` | `true` | Restart only when the pulled image ID changes |

The service iterates through declarative containers, runs `docker pull`, and restarts the matching systemd unit when needed. Unit names come from each container's `serviceName`, defaulting to `docker-<container-name>`.

The service logs `container_update_event` lines containing container name, image, service, old image ID, new image ID, and action. Pull failures cause the service to fail after all containers have been checked. It also sets `OnFailure=infra-update-report@%n.service`; with `secrets.infraAutomation` configured, that reporter creates or updates a Forgejo issue through the automatic update tooling.

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
  shell = pkgs.bashInteractive;
  home = "/home/docker";
  createHome = true;
  group = "docker";
  initialHashedPassword = "!";
};
```

The user has a fixed authorized key named `docker-volume-migration`. SSH access for this user is restricted by `ForceCommand` to Docker commands, SCP, and SFTP server commands needed by volume migration.

The private key for outbound migration is written by `deploy-docker-migration-key` from:

```nix
config.secrets.volumeMigration.file
```

The service writes `/home/docker/.ssh/volume-migration-key` with mode `0600` and configures SSH to use it.

The profile also grants members of the `docker` group passwordless sudo-rs access to run `ssh` and `test` as the `docker` user. This is used by `migrate-volumes`.

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
sudo -u docker test -f /home/docker/.ssh/volume-migration-key
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
