{
  description = "Reinitialized Infrastructure";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { 
        inherit system;
      };
      nixosSystem = nixpkgs.lib.nixosSystem;
    in {
      nixosConfigurations.devenv = nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
        };

        modules = [
          {
            # Import baseline configuration
            imports = [
              ./hardware/qemu.nix
              ./profiles/standard.nix
              ./modules/docker.nix
            ];

            # Define system-specific settings
            networking.hostName = "devenv";

            # Define required packages
            environment.systemPackages = with pkgs; [
              vim
              git
              curl
              btop
              fastfetch
              docker-compose

              nixd
            ];

            # Create develop user
            fileSystems."/home/develop" = {
              device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi2";
              fsType = "ext4";
              options = [ "defaults" ];

              autoResize = true;
              autoFormat = true;
            };
            users.users.develop = {
              extraGroups = [ "docker" "wheel" ];
              shell = pkgs.bashInteractive;

              isNormalUser = true;
              home = "/home/develop";
              initialPassword = "!";

              openssh.authorizedKeys.keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEgNNIkOFenuf9S6sy5heFeysErwMgfGD//r4jWgbg/E develop"
              ];
            };
          }
        ];
      };
    };
}