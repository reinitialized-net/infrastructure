{
  defaultStateVersion,
  self,
  nixpkgs ? self.inputs.nixpkgsStable,
  lib ? nixpkgs.lib,
  modulesPath ? "${self.inputs.nixpkgsStable}/nixos/modules",
}: host: {
  vmId,
  modules ? [],
  cores ? 2,
  memory ? 4096,
  system ? "x86_64-linux",
  hardware ? "qemu",
  disks ? [
    {
      storage = "hotData";
      size = 25;
    }
  ],
  networking ? {
    hostName = "nixVMA";
    bridge = "vmbr0";
    firewall = 0;
    useDHCP = true;
    ipAddress = null;
  }
}:
let
  vmaConfiguration = lib.nixosSystem {
    inherit system;
    specialArgs = {
      inherit self
      system
      nixpkgs;
    };
    modules = modules ++ [
      "${modulesPath}/image/repart.nix"
      "${self}/modules/hardware/${hardware}.nix"
      "${self}/modules/profiles/standard.nix"
      (if host == "standard" then {} else "${self}/modules/hosts/${host}.nix")
      ({
        config,
        lib,
        pkgs,
        ...
      }: let
        vma = import "${self}/overrides/vma.nix" { inherit pkgs; };
        qemuConfig = import "${self}/library/generateVMAImage/qemuConfig.nix" {
          inherit cores memory host vmId disks networking;
        };
        closureInfo = pkgs.closureInfo {
          rootPaths = [ config.system.build.toplevel ];
        };
        efiArch = pkgs.stdenv.hostPlatform.efiArch;
      in {
        # Emergency access configuration
        users.users.root.password = "";
        services.getty.autologinUser = "root";
        systemd.enableEmergencyMode = true;

        system.stateVersion = lib.mkForce defaultStateVersion;

        image.baseName = lib.mkDefault "vzdump-qemu-vm${toString vmId}";

        image.repart = {
          compression.enable = lib.mkDefault false;
          name = "vm-${toString vmId}-disk-1";

          partitions = {
            "10-esp" = {
              contents = {
                # systemd-boot EFI binary
                "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source =
                  "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
                # Linux kernel
                "/EFI/nixos/kernel.efi".source =
                  "${config.boot.kernelPackages.kernel}/${config.system.boot.loader.kernelFile}";
                # Initrd
                "/EFI/nixos/initrd".source =
                  "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";
                # Boot loader configuration
                "/loader/loader.conf".source = pkgs.writeText "loader.conf" ''
                  timeout 3
                  default nixos.conf
                '';
                # NixOS boot entry
                "/loader/entries/nixos.conf".source = pkgs.writeText "nixos.conf" ''
                  title NixOS
                  linux /EFI/nixos/kernel.efi
                  initrd /EFI/nixos/initrd
                  options init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams}
                '';
              };
              repartConfig = {
                Type = "esp";
                Label = "ESP";
                Format = "vfat";
                SizeMinBytes = "512M";
                SizeMaxBytes = "1G";
              };
            };
            "20-root" = {
              storePaths = [ config.system.build.toplevel ];
              contents = {
                # Registration file for nix-store --load-db on first boot
                "/nix-path-registration".source = "${closureInfo}/registration";
                # Essential NixOS marker - switch-to-configuration checks for this
                "/etc/NIXOS".source = pkgs.writeText "NIXOS" "";
              };
              repartConfig = {
                Type = "root";
                Label = "nixos";
                Format = "ext4";
                MakeDirectories = lib.concatStringsSep " " [
                  "/nix/var/nix/db"
                  "/nix/var/nix/gcroots"
                  "/nix/var/nix/profiles"
                  "/nix/var/nix/temproots"
                  "/nix/var/nix/userpool"
                  "/nix/var/nix/daemon-socket"
                  "/nix/var/log/nix/drvs"
                  "/var/empty"
                  "/var/lib"
                  "/var/log"
                  "/var/tmp"
                  "/tmp"
                  "/home"
                  "/root"
                  "/run"
                  "/etc/nixos"
                ];
                GrowFileSystem = true;
                SizeMinBytes = "${toString ((builtins.elemAt disks 0).size - 1)}G";
              };
            };
          };
        };

        # First-boot Nix store registration
        boot.postBootCommands = ''
          if [ -f /nix-path-registration ]; then
            set -euo pipefail
            ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration
            touch /etc/NIXOS
            ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
            rm -f /nix-path-registration
          fi
        '';

        system.build.VMA = pkgs.runCommand "buildVMA-${toString vmId}" {
          buildInputs = [ pkgs.zstd vma ];
          imageOut = config.system.build.image;
        } ''
          set -euo pipefail

          cat > qemu-server.conf <<'EOF'
${qemuConfig}
EOF

          backupBase="vzdump-qemu-${toString vmId}"

          ${pkgs.coreutils}/bin/cp --reflink=auto "$imageOut/${config.image.baseName}.${config.image.extension}" ./disk.raw

          # OVMF VARS (UEFI NVRAM)
          ovmfBase="${pkgs.OVMF.fd or pkgs.OVMF}"
          if [ -e "$ovmfBase/FV/OVMF_VARS_4M.fd" ]; then
            ovmfVars="$ovmfBase/FV/OVMF_VARS_4M.fd"
          elif [ -e "$ovmfBase/FV/OVMF_VARS.fd" ]; then
            ovmfVars="$ovmfBase/FV/OVMF_VARS.fd"
          else
            echo "OVMF VARS not found" >&2
            exit 1
          fi
          ${pkgs.coreutils}/bin/cp "$ovmfVars" ./efidisk0.raw
          ${pkgs.coreutils}/bin/chmod u+w ./efidisk0.raw
          ${pkgs.coreutils}/bin/truncate -s 4M ./efidisk0.raw

          # TPM state placeholder
          ${pkgs.coreutils}/bin/truncate -s 4M ./tpmstate0.raw

          ${vma}/bin/vma create "$backupBase.vma" \
            -c qemu-server.conf \
            "drive-scsi0=./disk.raw" \
            "drive-efidisk0=./efidisk0.raw" \
            "drive-tpmstate0=./tpmstate0.raw"

          ${pkgs.zstd}/bin/zstd "$backupBase.vma"

          mkdir -p "$out"
          mv "$backupBase.vma.zst" "$out/$backupBase.vma.zst"
        '';
      })
    ];
  };
in vmaConfiguration.config.system.build.VMA