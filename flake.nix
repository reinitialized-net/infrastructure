{
  description = "Reinitialized Infrastructure";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    vscode-server.url = "github:nix-community/nixos-vscode-server";
  };

  outputs = { self, nixpkgs, vscode-server, ... }@inputs:
    let
      system = "x86_64-linux";
      # pkgs = import nixpkgs { 
      #   inherit system;
      # };
      nixosSystem = nixpkgs.lib.nixosSystem;

      ## Helper function for creating configurations
      createVS = 
        {
          modules ? [ ]
        }:
        nixosSystem {
          inherit system;

          specialArgs = {
            inherit inputs;
          };

          modules = modules;
        };
    in {
      # Standard Configuration: Used for standing up new hosts
      nixosConfigurations.standard = createVS {
        modules = [
          ./hardware/qemu.nix
          ./modules/standard.nix
        ];
      };
      # devenv: NixOS-based Development Environment
      nixosConfigurations.devenv = createVS {
        modules = [
          ./hosts/devenv.nix
          inputs.vscode-server.nixosModules.default
        ];
      };
      # rp1: Primary Reverse Proxy
      nixosConfigurations.rp1 = createVS {
        modules = [
          ./hosts/rp1.nix
        ];
      };
      # apps1: Core Applications Host
      nixosConfigurations.apps1 = createVS {
        modules = [
          ./hosts/apps1.nix
        ];
      };
    };
}