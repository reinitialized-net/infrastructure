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
      device = "/dev/disk/by-partuuid/b1b2d2d0-3a3f-4c5b-9d9c-3b99d7c8e1f2";
      fsType = "ext4";

      autoResize = true;
    };
    "/boot" = lib.mkForce {
      device = "/dev/disk/by-partuuid/8d1d7c3e-1d2a-4f0e-b7a0-0a0e3f1f4a10";
      fsType = "vfat";

      neededForBoot = true;
    };
  };
  nixpkgs.hostPlatform = lib.mkForce "${system}";
  services.qemuGuest.enable = lib.mkForce true;
}