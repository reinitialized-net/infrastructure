{
  system,
  lib,
  pkgs,
  ...
}: {
  # UEFI boot configuration for Proxmox VMA images
  boot = {
    loader = {
      systemd-boot = {
        enable = lib.mkForce true;
        # Automatically detect and boot UKI images from /EFI/Linux/
        # This ensures systemd-boot is properly installed to ESP
        
        # Install systemd-boot to ESP on first boot to avoid warnings
        extraInstallCommands = lib.mkDefault ''
          ${pkgs.systemd}/bin/bootctl --esp-path=/boot install --no-variables || true
        '';
      };
      grub.enable = lib.mkForce false;
      # Don't modify EFI boot variables in VMs, but allow file installation
      efi.canTouchEfiVariables = lib.mkDefault false;
    };

    initrd = {
      # Enable systemd in initrd - this automatically enables UKI generation
      # UKI (Unified Kernel Image) bundles kernel + initrd + cmdline into a single .efi
      systemd.enable = lib.mkDefault true;
      
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
    ];
  };

  # Partition 1 = ESP (boot), Partition 2 = root (nixos)
  fileSystems = {
    "/" = lib.mkForce {
      device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0-part2";
      fsType = "ext4";
      autoResize = true;
    };
    "/boot" = lib.mkForce {
      device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0-part1";
      fsType = "vfat";
      options = [
        "fmask=0077"
        "dmask=0077"
      ];
      neededForBoot = true;
    };
  };

  nixpkgs.hostPlatform = lib.mkForce system;
  services.qemuGuest.enable = lib.mkForce true;
}