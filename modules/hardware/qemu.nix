{
  system,
  lib,
  ...
}: {
  # Configure systemd-boot for UEFI booting in QEMU
  boot = {
    loader = {
      systemd-boot.enable = lib.mkForce true;
      efi.canTouchEfiVariables = lib.mkForce true;
    };
    initrd = {
      availableKernelModules = [
        "virtio_net"
        "virtio_pci"
        "virtio_mmio"
        "virtio_scsi"
      ];
      kernelModules = [
        "virtio_balloon"
        "virtio_console"
        "virtio_rng"
        "virtio_gpu"
        "kvm-intel"
      ];
    };
  };
  # Define fileSystems
  fileSystems = {
    "/" = lib.mkForce {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";

      autoResize = true;
    };
    "/boot" = lib.mkForce {
      device = "/dev/disk/by-label/boot";
      fsType = "vfat";

      neededForBoot = true;
    };
  };
  nixpkgs.hostPlatform = lib.mkForce "${system}";
  services.qemuGuest.enable = lib.mkForce true;
}