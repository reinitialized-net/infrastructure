# How to install Virtual Server
1) Create Virtual Machine in Proxmox
```bash
TODO
```
2) Boot NixOS minimal and install
```bash
sudo -i && \
    gdisk /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0
```
```
### PARTITIONING INSTRUCTIONS
1) press n, enter, enter
2) type +600M, enter
3) set type to ef00, enter
4) press n, enter, enter, enter, enter
5) press w, then q
### END PARTITIONING INSTRUCTIONS
```
```bash
mkfs.fat -F 32 /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0-part1 &&\
    mkfs.ext4 /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0-part2 &&\
    mount /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0-part2 /mnt &&\
    mkdir /mnt/boot &&\
    mount /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0-part1 /mnt/boot &&\
    nixos-install --flake github:Reinitialized/infrastructure#CHANGEME
```
