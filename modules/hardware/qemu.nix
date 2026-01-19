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
      systemd.enable = lib.mkForce false;
      
      # Include default modules for broader hardware support
      includeDefaultModules = true;

      # Modules available in initrd (standard QEMU/KVM set)
      availableKernelModules = [
        "ahci"
        "xhci_pci"
        "virtio_pci"
        "virtio_blk"
        "virtio_scsi"
        "sd_mod"
        "sr_mod"
      ];

      # Force-load virtio-scsi stack
      kernelModules = [
        "virtio_pci"
        "virtio_scsi"
      ];

      supportedFilesystems = [ "ext4" "vfat" ];
    };

    growPartition = lib.mkDefault true;

    kernelParams = [
      "console=ttyS0,115200"
      "console=tty0"
      "boot.shell_on_fail"
      "boot.debug1"
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