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
      useDHCP = true;
    }
  ],
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
        lib,
        pkgs,
        config,
        ...  
      }: let
        vma = import "${self}/overrides/vma.nix" { inherit pkgs; };
        qemuConfig = import "${self}/library/generateVMAImage/qemuConfig.nix" {
          inherit cores memory host vmId disks networking enableProtection;
        };
        
        # Generate random 32-character password for rnetadmin
        randomPassword = lib.removeSuffix "\n" (builtins.readFile (
          pkgs.runCommand "generate-password" {} ''
            ${pkgs.openssl}/bin/openssl rand -base64 24 | tr -d '\n' | head -c 32 > $out
          ''
        ));
        
        hashedPassword = lib.removeSuffix "\n" (builtins.readFile (
          pkgs.runCommand "hash-password" {
            nativeBuildInputs = [ pkgs.mkpasswd ];
          } ''
            echo -n "${randomPassword}" | mkpasswd -m sha-512 -s | tr -d '\n' > $out
          ''
        ));
      in {
        system.stateVersion = lib.mkForce defaultStateVersion;
        image.baseName = lib.mkDefault "vzdump-qemu-vm${toString vmId}";
        image.extension = lib.mkDefault "vma.zst";
        
        # Set the generated password for rnetadmin
        users.users.rnetadmin.hashedPassword = lib.mkForce hashedPassword;

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

          ${vma}/bin/vma create "$backupBase.vma" \
            -c qemu-server.conf \
            "drive-scsi0=./disk.raw" \
            "drive-efidisk0=./efidisk0.raw" \
            "drive-tpmstate0=./tpmstate0.raw"

          ${pkgs.zstd}/bin/zstd "$backupBase.vma"

          mkdir -p "$out"
          mv "$backupBase.vma.zst" "$out/$backupBase.vma.zst"
          
          # Write password information to file
          cat > "$out/CREDENTIALS.txt" <<CREDS
==========================================================================
  IMPORTANT: SAVE THIS PASSWORD IN YOUR DOCUMENTATION
==========================================================================
  VM ID: ${toString vmId}
  Hostname: ${host}
  Username: rnetadmin
  Password: ${randomPassword}
==========================================================================
  Save this password in your password manager or documentation.
  Delete this file after saving the credentials securely.
==========================================================================
CREDS

          echo ""
          echo "=========================================================================="
          echo "  VM built successfully!"
          echo "  CREDENTIALS FILE: \$out/CREDENTIALS.txt"
          echo "  ** CHECK THE CREDENTIALS.txt FILE FOR LOGIN PASSWORD **"
          echo "=========================================================================="
          echo ""
        '';
      })
    ];
  };
in vmaConfiguration.config.system.build.VMA