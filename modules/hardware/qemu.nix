{
  system,
  lib,
  pkgs,
  ...
}: {
  # UEFI boot configuration for Proxmox VMA images
  boot = {
    loader = {
      systemd-boot.enable = lib.mkForce false;
      grub.enable = lib.mkForce false;
      efi.canTouchEfiVariables = lib.mkForce false;
    };

    initrd = {
      # Use traditional busybox initrd for reliability and emergency shell access
      systemd.enable = lib.mkForce false;

      # Modules available in initrd
      availableKernelModules = [
        # VirtIO transport (must load before device drivers)
        "virtio_pci"
        # VirtIO SCSI for Proxmox virtio-scsi-single controller
        "virtio_scsi"
        # SCSI disk support
        "sd_mod"
        # Filesystem support
        "ext4"
        "vfat"
        "nls_cp437"
        "nls_iso8859_1"
      ];

      # Force-load these modules early in initrd
      kernelModules = [
        "virtio_pci"
        "virtio_scsi"
        "sd_mod"
      ];

      supportedFilesystems = [ "ext4" "vfat" ];
    };

    growPartition = lib.mkDefault true;

    # Minimal kernel parameters
    kernelParams = [
      "console=tty0"
      "console=ttyS0,115200"
    ];
  };

  # Use /dev/sda partitions directly - more reliable than by-partlabel in initrd
  # Partition 1 = ESP (boot), Partition 2 = root (nixos)
  fileSystems = {
    "/" = lib.mkForce {
      device = "/dev/sda2";
      fsType = "ext4";
      autoResize = true;
    };
    "/boot" = lib.mkForce {
      device = "/dev/sda1";
      fsType = "vfat";
      neededForBoot = true;
    };
  };

  nixpkgs.hostPlatform = lib.mkForce system;
  services.qemuGuest.enable = lib.mkForce true;
}