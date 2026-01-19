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
        vma = import "${self}/overrides/vma.nix" { 
          inherit pkgs; 
        };
        qemuConfig = import "${self}/library/generateVMAImage/qemuConfig.nix" {
          inherit cores memory host vmId disks networking;
        };
        # Create closure info for Nix database registration
        closureInfo = pkgs.closureInfo {
          rootPaths = [ config.system.build.toplevel ];
        };
        efiArch = pkgs.stdenv.hostPlatform.efiArch;
      in {
        system.stateVersion = lib.mkForce defaultStateVersion;

        image.baseName = lib.mkDefault "vzdump-qemu-vm${toString vmId}";

        image.repart = {
          compression.enable = lib.mkDefault false;
          name = "vm-${toString vmId}-disk-1";

          partitions = {
            "10-esp" = {
              contents = {
                "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source =
                  "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
                "/EFI/Linux/${config.system.boot.loader.ukiFile}".source =
                  "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
                # systemd-boot configuration
                "/loader/loader.conf".source = pkgs.writeText "loader.conf" ''
                  timeout 3
                  default ${config.system.boot.loader.ukiFile}
                  editor no
                '';
              };
              repartConfig = {
                Type = "esp";
                Label = "boot";
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
                # Create all essential directories for a functional NixOS system
                MakeDirectories = lib.concatStringsSep " " [
                  # Nix-related directories
                  "/nix/var"
                  "/nix/var/nix"
                  "/nix/var/nix/db"
                  "/nix/var/nix/gcroots"
                  "/nix/var/nix/profiles"
                  "/nix/var/nix/temproots"
                  "/nix/var/nix/userpool"
                  "/nix/var/nix/daemon-socket"
                  "/nix/var/log"
                  "/nix/var/log/nix"
                  "/nix/var/log/nix/drvs"
                  # Standard FHS directories
                  "/bin"
                  "/sbin"
                  "/usr"
                  "/usr/bin"
                  "/var"
                  "/var/empty"
                  "/var/lib"
                  "/var/log"
                  "/var/tmp"
                  "/tmp"
                  "/home"
                  "/root"
                  "/run"
                  "/mnt"
                  "/etc"
                  "/etc/nixos"
                ];
                GrowFileSystem = true;
                SizeMinBytes = "${toString ((builtins.elemAt disks 0).size - 1)}G";
              };
            };
          };
        };

        # First-boot initialization script - canonical NixOS pattern
        # This registers the Nix store paths and sets up the system profile
        boot.postBootCommands = ''
          # On the first boot, register Nix store paths and set up the system profile
          if [ -f /nix-path-registration ]; then
            set -euo pipefail
            echo "Performing first-boot NixOS initialization..."

            # Register the contents of the initial Nix store
            ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration

            # nixos-rebuild requires a "system" profile and /etc/NIXOS marker
            touch /etc/NIXOS
            ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system

            # Prevent this from running on subsequent boots
            rm -f /nix-path-registration
            
            echo "First-boot initialization complete."
          fi
        '';

        system.build.VMA = pkgs.runCommand "buildVMA-${toString vmId}" {
          buildInputs = [
            pkgs.zstd
            vma
          ];
          # Ensure the disk image derivation is built first.
          imageOut = config.system.build.image;
        } ''
          set -euo pipefail

          # Create qemu-server.conf
          cat > qemu-server.conf <<'EOF'
${qemuConfig}
EOF

          # Proxmox vzdump naming convention (deterministic in Nix builds)
          backupBase="vzdump-qemu-${toString vmId}"
          
          # Copy (not symlink) into the build directory for vma tooling.
          ${pkgs.coreutils}/bin/cp --reflink=auto --preserve=mode,timestamps "$imageOut/${config.image.baseName}.${config.image.extension}" ./disk.raw

          # Populate efidisk0 with OVMF VARS (UEFI NVRAM template) and pad to 4M.
          # Note: Proxmox stores firmware code separately; efidisk0 is the VARS/NVRAM image.
          # Nixpkgs typically provides these firmware blobs via the `fd` output.
          ovmfBase="${pkgs.OVMF.fd or pkgs.OVMF}"
          if [ -e "$ovmfBase/FV/OVMF_VARS_4M.fd" ]; then
            ovmfVars="$ovmfBase/FV/OVMF_VARS_4M.fd"
          elif [ -e "$ovmfBase/FV/OVMF_VARS.fd" ]; then
            ovmfVars="$ovmfBase/FV/OVMF_VARS.fd"
          else
            echo "Could not find OVMF VARS template under $ovmfBase/FV" >&2
            ls -al "$ovmfBase" >&2 || true
            ls -al "$ovmfBase/FV" >&2 || true
            exit 1
          fi
          ${pkgs.coreutils}/bin/cp --preserve=timestamps "$ovmfVars" ./efidisk0.raw
          ${pkgs.coreutils}/bin/chmod u+w ./efidisk0.raw
          ${pkgs.coreutils}/bin/truncate -s 4M ./efidisk0.raw

          # Create TPM state placeholder (4M) and pad.
          ${pkgs.coreutils}/bin/truncate -s 4M ./tpmstate0.raw

          driveScsi0=./disk.raw
          driveEfi0=./efidisk0.raw
          driveTpm0=./tpmstate0.raw

          # Build the VMA archive
          ${vma}/bin/vma create "$backupBase.vma" \
            -c qemu-server.conf \
            "drive-scsi0=$driveScsi0" \
            "drive-efidisk0=$driveEfi0" \
            "drive-tpmstate0=$driveTpm0"

          # Compress the VMA archive
          ${pkgs.zstd}/bin/zstd "$backupBase.vma"

          # Move the final artifact to the output
          mkdir -p "$out"
          mv "$backupBase.vma.zst" "$out/$backupBase.vma.zst"
        '';
      })
    ];
  };
in vmaConfiguration.config.system.build.VMA