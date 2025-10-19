# hardware/qemu.nix
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = 
    [
      (modulesPath + "/profiles/qemu-guest.nix")
    ];

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    initrd = {
      availableKernelModules = [ "uhci_hcd" "ehci_pci" "ahci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
      kernelModules = [ ];
    };
    kernelModules = [ "kvm-intel" ];
    extraModulePackages = [ ];
  };

  fileSystems = {
    "/boot" = lib.mkDefault {
      device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0-part1";
      fsType = "vfat";
    };
    "/" = lib.mkDefault {
      device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0-part2";
      fsType = "ext4";

      autoResize = true;
    };
  };

  networking = {
    useDHCP = lib.mkDefault true;
    hostName = lib.mkDefault "nixos-qemu";
  };

  nixpkgs = {
    hostPlatform = lib.mkDefault "x86_64-linux";
  };
  
  services = {
    qemuGuest = {
      enable = true;
    };
  };

  swapDevices = [ ];
}

