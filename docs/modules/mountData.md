# Mount Data Profile

**Module Path:** `modules/profiles/mountData.nix`

**Import:** Import explicitly when needed

## Overview

Simple profile for mounting and managing a secondary data disk, typically used for storing application data, Docker volumes, or databases. Designed for VMs with multiple disks where the second disk (scsi1) is dedicated to data storage.

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

If the disk is unformatted on first boot, it will be automatically formatted with ext4:

```
mkfs.ext4 /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1
```

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

Use Proxmox backup features to snapshot the entire VM.

#### Manual Backup

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

Manually format:

```bash
sudo mkfs.ext4 -L data /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1
```

Then mount:

```bash
sudo mount /mnt/data
```

### Permission Issues

Set ownership:

```bash
sudo chown -R user:group /mnt/data
```

Or for Docker:

```bash
sudo chown -R docker:docker /mnt/data/docker
```

### Disk Full

Clean up space:

```bash
# Find large directories
du -sh /mnt/data/* | sort -h

# Clean up Docker (if using containers profile)
docker system prune -a --volumes
```

## Dependencies

- None - standalone profile

## Required By

- [Containers Profile](containers.md) - Uses data disk for Docker storage

## Alternative Configurations

### Different Mount Point

```nix
{
  # Override the mount point
  fileSystems."/data" = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1";
    fsType = "ext4";
    autoFormat = true;
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
    autoFormat = true;
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
