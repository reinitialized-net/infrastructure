{
  lib,
  system,
  ...
}:
{
  boot = {
    initrd = {
      availableKernelModules = [
        "xhci_pci"
        "ahci"
        "nvme"
        "usb_storage"
        "uas"
        "sd_mod"
        "sr_mod"
      ];
      systemd.enable = true;
    };
    kernelModules = [ "kvm-intel" ];
    loader = {
      grub.enable = false;
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    supportedFilesystems = [ "ext4" ];
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
      options = [ "noatime" ];
    };
    "/boot" = {
      device = "/dev/disk/by-label/BOOT";
      fsType = "vfat";
      options = [
        "fmask=0077"
        "dmask=0077"
      ];
      neededForBoot = true;
    };
    "/var/lib/llama-cpp" = {
      device = "/dev/disk/by-label/AI-MODELS";
      fsType = "ext4";
      options = [ "noatime" ];
      neededForBoot = true;
    };
  };

  swapDevices = [
    {
      device = "/swapfile";
      size = 32768;
    }
  ];

  hardware = {
    cpu.intel.updateMicrocode = true;
    enableRedistributableFirmware = true;
  };

  services.fstrim.enable = true;
  nixpkgs.hostPlatform = lib.mkForce system;
}
