{
  system,
  lib,
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

      # Modules available in initrd
      availableKernelModules = [
        "uhci_hcd"
        "ehci_pci"
        "ahci"
        "virtio_pci"
        "virtio_scsi"
        "sd_mod"
        "sr_mod"
      ];

      # Force-load virtio-scsi stack and input
      kernelModules = [
        "kvm-intel"
      ];

      supportedFilesystems = [ "ext4" "vfat" ];
    };

    growPartition = lib.mkDefault true;

    kernelParams = [
      "console=ttyS0,115200"
      "console=tty0"
      "boot.shell_on_fail"
    ];
  };

  # Use /dev/sda partitions directly - more reliable than by-partlabel in initrd
  # Partition 1 = ESP (boot), Partition 2 = root (nixos)
  fileSystems = {
    "/" = lib.mkForce {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
      autoResize = true;
    };
    "/boot" = lib.mkForce {
      device = "/dev/disk/by-label/BOOT";
      fsType = "vfat";
      neededForBoot = true;
    };
  };

  nixpkgs.hostPlatform = lib.mkForce system;
  services.qemuGuest.enable = lib.mkForce true;
}