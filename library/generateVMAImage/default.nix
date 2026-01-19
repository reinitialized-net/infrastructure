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
        systemClosure = pkgs.closureInfo {
          rootPaths = [ config.system.build.toplevel ];
        };
      in {
        system.stateVersion = lib.mkForce defaultStateVersion;

        image.baseName = lib.mkDefault "vzdump-qemu-vm${toString vmId}";
        image.extension = lib.mkDefault "vma.zst";

        image.repart = let
          efiArch = pkgs.stdenv.hostPlatform.efiArch;
          ukiFile = config.system.boot.loader.ukiFile or "uki-linux-${efiArch}.img";
          ukiPath = "${config.system.build.uki}/${ukiFile}";
          bootPartuuid = "8d1d7c3e-1d2a-4f0e-b7a0-0a0e3f1f4a10";
          rootPartuuid = "b1b2d2d0-3a3f-4c5b-9d9c-3b99d7c8e1f2";
        in {
          name = "vm-${toString vmId}-disk-1";

          partitions = {
            "esp" = {
              contents = {
                UUID = bootPartuuid;
                "/EFI/Linux/${ukiFile}".source =
                  "${ukiPath}";
                # systemd-boot configuration
                "/loader/loader.conf".source = (pkgs.writeText "$out" ''
                  timeout 3
                '');
              };
              repartConfig = {
                Type = "esp";
                Label = "boot";
                FileSystemLabel = "boot";
                Format = "vfat";
                UUID = rootPartuuid;
                SizeMaxBytes = "1G";
              };
            };
            "root" = {
              storePaths = [ config.system.build.toplevel ];
              contents = {
                "/nix-path-registration".source = "${systemClosure}/registration";
              };
              repartConfig = {
                Type = "root";
                Label = "nixos";
                Format = "ext4";
                GrowFileSystem = true;
                SizeMinBytes = "${toString ((builtins.elemAt disks 0).size - 1)}G";
              };
            };
          };
        };

        boot.postBootCommands = lib.mkAfter ''
          if [ -f /nix-path-registration ]; then
            set -euo pipefail
            ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration
            touch /etc/NIXOS
            ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
            rm -f /nix-path-registration
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
          ${pkgs.coreutils}/bin/cp --reflink=auto --preserve=mode,timestamps "$imageOut/${config.image.repart.name}.raw" ./disk.raw

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