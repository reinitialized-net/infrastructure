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
      systemd.enable = lib.mkForce true;
      availableKernelModules = [
        "virtio_net"
        "virtio_pci"
        "virtio_mmio"
        "virtio_scsi"
        "virtio_blk"
        "scsi_mod"
        "sd_mod"
        "sr_mod"
        "uas"
      ];
      kernelModules = [
        "virtio_balloon"
        "virtio_console"
        "virtio_rng"
        "virtio_gpu"
        "virtio_pci"
        "virtio_mmio"
        "virtio_scsi"
        "virtio_blk"
        "scsi_mod"
        "sd_mod"
        "sr_mod"
        "kvm-intel"
      ];
      supportedFilesystems = [ "ext4" "vfat" ];
    };
    growPartition = lib.mkDefault true;
  };
  # Define fileSystems using GPT partition labels (by-partlabel)
  # Note: repartConfig.Label sets the GPT partition label, not filesystem label
  fileSystems = {
    "/" = lib.mkForce {
      device = "/dev/disk/by-partlabel/nixos";
      fsType = "ext4";
      autoResize = true;
    };
    "/boot" = lib.mkForce {
      device = "/dev/disk/by-partlabel/boot";
      fsType = "vfat";
      neededForBoot = true;
    };
  };
  nixpkgs.hostPlatform = lib.mkForce "${system}";
  services.qemuGuest.enable = lib.mkForce true;
}