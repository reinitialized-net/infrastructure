# Mount Data Profile

**Module Path:** `modules/profiles/mountData.nix`

**Import:** Import explicitly when needed

## Overview

Simple profile for mounting and managing a secondary data disk, typically used for storing application data, Docker volumes, or databases. Designed for VMs with multiple disks where the second disk (scsi1) is dedicated to data storage.

The profile enables automatic formatting. For a new VM, attach a deliberately provisioned blank data disk. Before applying it to an existing VM, verify the disk identity, filesystem, and recoverable backups. Never attach an arbitrary or recovery disk as `scsi1` and assume it is safe to initialize.

## Features

- Automatic mounting of second disk
- Auto-formatting on first boot
- Auto-resizing support
- ext4 filesystem
- Mounts at `/mnt/data`

## Configuration

```nix
{
  fileSystems."/mnt/data" = lib.mkForce {
    fsType = "ext4";
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1";
    options = [ "defaults" ];
    
    autoFormat = true;
    autoResize = true;
  };
}
```

## What It Does

### Disk Detection

Expects the data disk to be the second SCSI disk:

- **OS Disk**: `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0`
- **Data Disk**: `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1`

### Automatic Formatting

`autoFormat = true` asks NixOS to initialize an unformatted disk with ext4. This is provisioning behavior. A failed mount or filesystem probe on an existing disk requires investigation before any formatting; formatting destroys the previous contents.

### Automatic Resizing

If the disk is resized in Proxmox, the filesystem will automatically expand on next boot.

### Mount Point

Data is mounted at `/mnt/data` with standard mount options.

## Usage

### In VM Images

When building VM images with multiple disks using `makeDualExport`:

```nix
let
  dualSystems = {
    my-vm = library.makeDualExport "my-vm" {
      system = "x86_64-linux";
      vmId = 100;
      
      disks = [
        {
          storage = "local-lvm";
          size = 50;  # OS disk (scsi0)
        }
        {
          storage = "local-lvm";
          size = 500;  # Data disk (scsi1)
        }
      ];
      
      modules = [
        "${inputs.self}/modules/profiles/mountData.nix"
        {
          # Data disk is now available at /mnt/data
        }
      ];
    };
  };
in
{
  nixosConfigurations.my-vm = dualSystems.my-vm.nixosSystem;
  packages.x86_64-linux.my-vm = dualSystems.my-vm.package;
}
```

### With Docker/Containers

Required by the containers profile:

```nix
{
  imports = [
    ./modules/profiles/mountData.nix
    ./modules/profiles/containers
  ];
  
  # Docker data will be stored on /mnt/data/docker
}
```

### With Databases

Store database data on the data disk:

```nix
{
  imports = [
    ./modules/profiles/mountData.nix
  ];
  
  services.postgresql = {
    enable = true;
    dataDir = "/mnt/data/postgres";
  };
}
```

### With Applications

Store application data:

```nix
{
  imports = [
    ./modules/profiles/mountData.nix
  ];
  
  systemd.services.myapp = {
    serviceConfig = {
      Environment = "DATA_DIR=/mnt/data/myapp";
    };
  };
}
```

## Directory Structure Example

After mounting, organize your data:

```
/mnt/data/
├── docker/              # Docker volumes and containers
│   ├── volumes/
│   ├── containers/
│   └── image/
├── postgres/           # PostgreSQL database
│   ├── base/
│   ├── global/
│   └── pg_wal/
├── uploads/            # Application uploads
├── backups/            # Backup storage
└── logs/              # Application logs
```

## Managing the Data Disk

### Check Disk Usage

```bash
df -h /mnt/data
```

### Check Filesystem

```bash
lsblk
mount | grep /mnt/data
```

### Resize Disk

Confirm that this is the intended ext4 filesystem and retain a verified backup before changing disk size. Expansion does not provide a way to shrink the filesystem or recover corruption.

1. Resize the disk in Proxmox UI
2. Reboot the VM
3. The filesystem will auto-expand

Or manually:

```bash
# Resize filesystem
resize2fs /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1
```

### Backup Data Disk

#### Snapshot in Proxmox

Use Proxmox backup features to snapshot the entire VM, with application quiescing or a database-aware backup plan. Verify restoration; a snapshot of a running database alone does not establish application consistency.

#### Manual Backup

Stop application writers or use a consistent read-only snapshot before copying data. The following file copies are not hot database backups. Preserve application ownership and verify a restore before relying on them for a migration.

```bash
# Tar backup
tar -czf /backup/data-backup.tar.gz /mnt/data

# Rsync to remote
rsync -av /mnt/data/ remote:/backup/data/
```

### Verify Mounting

```bash
# Check if mounted
mountpoint /mnt/data

# Check disk info
lsblk -f | grep scsi1

# Check filesystem
sudo tune2fs -l /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1
```

## Troubleshooting

### Disk Not Mounting

Check if disk exists:

```bash
ls -l /dev/disk/by-id/ | grep scsi
```

Expected output:
```
scsi-0QEMU_QEMU_HARDDISK_drive-scsi0 -> ../../sda
scsi-0QEMU_QEMU_HARDDISK_drive-scsi1 -> ../../sdb
```

### Formatting Failed

On an existing production disk, preserve the contents and diagnose the failure:

```bash
lsblk -o NAME,PATH,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS
sudo blkid -p /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1
journalctl -b -u mnt-data.mount
```

Confirm the Proxmox disk assignment and inspect filesystem errors. If the disk contains data or its history is uncertain, take a recovery image or snapshot and use a filesystem-specific recovery plan. Do not run `mkfs` as a mount repair. Initializing a replacement disk is a separate destructive provisioning operation requiring an identified blank target and a recovery plan for the old disk.

### Permission Issues

Inspect ownership and verify the backing filesystem is mounted:

```bash
mountpoint /mnt/data
ls -ldn /mnt/data /mnt/data/docker
```

Use the affected service's declared UID/GID and tmpfiles rules to correct only its intended paths. Do not recursively change ownership across `/mnt/data` or Docker volumes: different services, especially databases, require different owners. See [Using makeUser](../examples/makeUser.md#troubleshooting) for managed user directories.

### Disk Full

Identify the space consumer first:

```bash
# Find large directories
du -sh /mnt/data/* | sort -h

# Inspect Docker usage without deleting data
docker system df -v
```

Remove only identified disposable data after checking its owner and recovery needs. Do not prune volumes during an incident or migration: unused or anonymous volumes may contain a disconnected database. For stale CI containers, inspect the stopped jobs before targeted cleanup; see the [runner disk-space investigation](../investigations/forgejo-runner-disk-space-stale-containers.md).

## Dependencies

- None - standalone profile

## Required By

- [Containers Profile](containers.md) - Uses data disk for Docker storage

## Alternative Configurations

These examples are separate profiles, not overrides of `mountData`'s forced `/mnt/data` definition. They require an already prepared filesystem on a verified target and disable automatic formatting. Changing the declared filesystem type does not convert existing data; plan a backed-up migration first.

### Different Mount Point

```nix
{
    # Use an already prepared data filesystem at a different mount point
  fileSystems."/data" = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1";
    fsType = "ext4";
    autoFormat = false;
    autoResize = true;
  };
}
```

### XFS Instead of ext4

```nix
{
  fileSystems."/mnt/data" = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1";
    fsType = "xfs";
    options = [ "defaults" "noatime" ];
    autoFormat = false;
  };
}
```

### Custom Disk ID

For non-QEMU systems:

```nix
{
  fileSystems."/mnt/data" = {
    device = "/dev/sdb1";  # Or specific device
    fsType = "ext4";
    options = [ "defaults" ];
  };
}
```

## See Also

- [Containers Profile](containers.md) - Uses this for Docker storage
- [Examples](../examples.md) - Usage in VM configurations
