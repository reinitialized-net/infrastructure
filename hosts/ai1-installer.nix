{
  lib,
  pkgs,
  targetSystem,
  ...
}:
let
  installAi1 = pkgs.writeShellApplication {
    name = "install-ai1";
    runtimeInputs = with pkgs; [
      coreutils
      dosfstools
      e2fsprogs
      gawk
      gnugrep
      gptfdisk
      nixos-install-tools
      parted
      systemd
      util-linux
    ];
    text = ''
      usage() {
        echo "Usage: sudo install-ai1 SYSTEM_DISK MODEL_DISK"
        echo "Example: sudo install-ai1 /dev/sda /dev/sdb"
        echo
        echo "Both disks are completely erased. SYSTEM_DISK receives NixOS; MODEL_DISK stores llama.cpp models."
      }

      if [[ $EUID -ne 0 ]]; then
        echo "ERROR: install-ai1 must run as root; use sudo." >&2
        exit 1
      fi

      if [[ $# -ne 2 ]]; then
        usage
        exit 1
      fi

      system_device=$(readlink -f "$1")
      model_device=$(readlink -f "$2")

      if [[ $system_device == "$model_device" ]]; then
        echo "ERROR: SYSTEM_DISK and MODEL_DISK must be different devices." >&2
        exit 1
      fi

      if [[ ! -d /sys/firmware/efi ]]; then
        echo "ERROR: Boot this USB in UEFI mode before installing." >&2
        exit 1
      fi

      for device in "$system_device" "$model_device"; do
        if [[ ! -b $device || $(lsblk -dn -o TYPE "$device") != "disk" ]]; then
          echo "ERROR: '$device' is not a whole block device." >&2
          exit 1
        fi

        if lsblk -nrpo MOUNTPOINT "$device" | grep -q '[^[:space:]]'; then
          echo "ERROR: '$device' or one of its partitions is mounted. Refusing to erase it." >&2
          exit 1
        fi
      done

      echo "The following disks will be DESTROYED:"
      lsblk -d -o NAME,SIZE,MODEL,SERIAL "$system_device" "$model_device"
      echo
      read -r -p "Type 'ERASE ai1' to continue: " confirmation
      if [[ $confirmation != "ERASE ai1" ]]; then
        echo "Installation cancelled."
        exit 1
      fi

      wipefs --all --force "$system_device" "$model_device"
      sgdisk --zap-all "$system_device"
      sgdisk --zap-all "$model_device"

      parted --script "$system_device" \
        mklabel gpt \
        mkpart ESP fat32 1MiB 1025MiB \
        set 1 esp on \
        mkpart root ext4 1025MiB 100%
      parted --script "$model_device" \
        mklabel gpt \
        mkpart models ext4 1MiB 100%

      partprobe "$system_device" "$model_device"
      udevadm settle

      partition() {
        lsblk -lnpo NAME,PARTN "$1" | awk -v number="$2" '$2 == number { print $1; exit }'
      }

      efi_partition=$(partition "$system_device" 1)
      root_partition=$(partition "$system_device" 2)
      model_partition=$(partition "$model_device" 1)

      for partition_path in "$efi_partition" "$root_partition" "$model_partition"; do
        if [[ ! -b $partition_path ]]; then
          echo "ERROR: Failed to discover a newly-created partition." >&2
          exit 1
        fi
      done

      mkfs.fat -F 32 -n BOOT "$efi_partition"
      mkfs.ext4 -F -L nixos -m 1 "$root_partition"
      mkfs.ext4 -F -L AI-MODELS -m 0 "$model_partition"

      cleanup() {
        mountpoint -q /mnt/var/lib/llama-cpp && umount /mnt/var/lib/llama-cpp
        mountpoint -q /mnt/boot && umount /mnt/boot
        mountpoint -q /mnt && umount /mnt
      }
      trap cleanup EXIT

      mount "$root_partition" /mnt
      mkdir -p /mnt/boot /mnt/var/lib/llama-cpp
      mount "$efi_partition" /mnt/boot
      mount "$model_partition" /mnt/var/lib/llama-cpp

      nixos-install \
        --root /mnt \
        --system ${targetSystem} \
        --no-root-password \
        --no-channel-copy

      sync
      cleanup
      trap - EXIT

      echo
      echo "ai1 is installed. Remove the USB and reboot."
      echo "After boot: ssh rnetadmin@10.1.13.10"
    '';
  };
in
{
  image.baseName = lib.mkForce "nixos-ai1-installer";
  isoImage = {
    edition = "ai1";
    storeContents = [ targetSystem ];
  };

  environment.systemPackages = [
    installAi1
    pkgs.nvme-cli
    pkgs.pciutils
  ];

  services.getty.helpLine = lib.mkAfter ''

    Install the dedicated ai1 host with:
      sudo install-ai1 SYSTEM_DISK MODEL_DISK

    Run lsblk -d -o NAME,SIZE,MODEL,SERIAL first. Both selected disks will be erased.
  '';
}
