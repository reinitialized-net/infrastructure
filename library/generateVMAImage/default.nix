{
  defaultStateVersion,
  self,
  nixpkgs ? self.inputs.nixpkgsStable,
  modulesPath ? "${self.inputs.nixpkgsStable}/nixos/modules",
}: host: {
  vmId,
  modules ? [],
  cores ? 2,
  memory ? 4096,
  system ? "x86_64-linux",
  hardware ? "qemu",
  includeSecrets ? true,
  enableProtection ? true,
  disks ? [
    {
      storage = "hotData";
      size = 25;
    }
  ],
  networking ? [
    {
      bridge = "vmbr0";
      firewall = false;
      vlan = 200;
    }
  ],
}:
let
  vmaConfiguration = import "${self}/library/makeConfiguration.nix" {
    inherit defaultStateVersion self nixpkgs;
  } host {
    inherit system hardware includeSecrets;

    modules = modules ++ [
      "${modulesPath}/image/repart.nix"
      ({
        lib,
        pkgs,
        config,
        ...  
      }: let
        vma = import "${self}/overrides/vma.nix" { inherit pkgs; };
        qemuConfig = import "${self}/library/generateVMAImage/qemuConfig.nix" {
          inherit cores memory host vmId disks networking enableProtection;
        };
      in {
        system.stateVersion = lib.mkForce defaultStateVersion;
        image.baseName = lib.mkDefault "vzdump-qemu-vm${toString vmId}";
        image.extension = lib.mkDefault "vma.zst";
        
        # VMA access is key-only; never place a bootstrap password in the store.
        users.users.rnetadmin.hashedPassword = lib.mkForce "!";

        image.repart = let
          efiArch = pkgs.stdenv.hostPlatform.efiArch;
          ukiFile = config.system.boot.loader.ukiFile or "uki-linux-${efiArch}.efi";
          ukiPath = "${config.system.build.uki}/${ukiFile}";
        in {
          name = "vm-${toString vmId}-disk-1";

          partitions = {
            "10-esp" = {
              contents = {
                "/EFI/BOOT/BOOT${lib.toUpper (lib.toUpper efiArch)}.EFI".source =
                  "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
                "/EFI/Linux/${ukiFile}".source =
                  "${ukiPath}";
                # systemd-boot configuration
                "/loader/loader.conf".source = (pkgs.writeText "$out" ''
                  timeout 3
                '');
              };
              repartConfig = {
                Type = "esp";
                Label = "BOOT";
                UUID = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b";
                Format = "vfat";
                SizeMinBytes = "1G";
                SizeMaxBytes = "1G";
              };
            };
            "20-root" = {
              storePaths = [ 
                config.system.build.toplevel
                config.system.build.kernel  
              ];
              repartConfig = {
                Type = "root";
                Label = "nixos";
                Format = "ext4";
                GrowFileSystem = true;
                SizeMinBytes = "${toString ((builtins.elemAt disks 0).size - 1)}G";
                SizeMaxBytes = "${toString ((builtins.elemAt disks 0).size - 1)}G";
              };
            };
          };
        };

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

          # Create placeholder disk images for additional SCSI disks (scsi1, scsi2, etc.)
          # scsi0 is the OS disk (disk.raw), additional disks are empty placeholders
${lib.concatStringsSep "\n" (lib.genList (i: 
  if i == 0 then 
    "          # scsi0 uses the OS disk image (disk.raw)"
  else
    "          ${pkgs.coreutils}/bin/truncate -s ${toString (builtins.elemAt disks i).size}G ./scsi${toString i}.raw"
) (builtins.length disks))}

          ${vma}/bin/vma create "$backupBase.vma" \
            -c qemu-server.conf \
${lib.concatStringsSep " \\\n" (lib.genList (i:
  if i == 0 then
    "            \"drive-scsi0=./disk.raw\""
  else
    "            \"drive-scsi${toString i}=./scsi${toString i}.raw\""
) (builtins.length disks))} \
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
