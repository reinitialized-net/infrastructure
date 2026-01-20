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

      # Modules available in initrd
      availableKernelModules = [
        # Storage
        "ahci"
        "xhci_pci"
        "virtio_pci"
        "virtio_blk"
        "virtio_scsi"
        "sd_mod"
        "sr_mod"
        # USB and input for keyboard
        "uhci_hcd"
        "ehci_pci"
        "xhci_hcd"
        "usbhid"
        "hid_generic"
        "hid"
      ];

      # Force-load virtio-scsi stack and input
      kernelModules = [
        "virtio_pci"
        "virtio_scsi"
        "usbhid"
        "hid_generic"
      ];

      supportedFilesystems = [ "ext4" "vfat" ];
    };

    growPartition = lib.mkDefault true;

    kernelParams = [
      "console=ttyS0,115200"
      "console=tty0"
      "rootdelay=10"
      "scsi_mod.scan=sync"
      "boot.shell_on_fail"
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