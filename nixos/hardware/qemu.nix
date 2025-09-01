# hardware/qemu.nix
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = 
    [
      (modulesPath + "/profiles/qemu-guest.nix")
    ];

  boot = {
    loader = {
      # Use systemd-boot for UEFI booting
      systemd-boot.enable = true;
      # Not entirely sure what this does, but it was enabled by default.
      efi.canTouchEfiVariables = true;
    };
    initrd = {
      # Ensure we have the correct kernel modules for hardware profile
      availableKernelModules = [ "uhci_hcd" "ehci_pci" "ahci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
      kernelModules = [ ];
    };
    #  Ensure we have the correct kernel modules for hardware profile
    kernelModules = [ "kvm-intel" ];
    extraModulePackages = [ ];
  };
  # Define FileSystems
  fileSystems = {
    "/boot" = lib.mkDefault {
      device = "/dev/disk/by-label/BOOT";
      fsType = "vfat";
    };
    "/" = lib.mkDefault {
      device = "/dev/disk/by-label/os";
      fsType = "ext4";

      autoResize = true;
    };
  };
  networking = {
    # Enable DHCP by default
    useDHCP = lib.mkDefault true;
    # Set default hostname for QEMU guests
    hostName = lib.mkDefault "nixos-qemu";
  };
  nixpkgs = {
    hostPlatform = lib.mkDefault "x86_64-linux";
  };
  services = {
    # Enable the QEMU Guest Agent service for better integration
    qemuGuest = {
      enable = true;
    };
  };

  swapDevices = [ ];
  system.stateVersion = "25.05";
}