{
  lib,
  ...
}: {
  fileSystems = {
    "/mnt/data" = lib.mkForce {
      fsType = "ext4";
      device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1";
      options = [ "defaults" ];

      autoFormat = true;
      autoResize = true;
    };
  };
}