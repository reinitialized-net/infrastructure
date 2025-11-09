{
  description = "Reinitialized Infrastructure";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    vscode-server.url = "github:nix-community/nixos-vscode-server";
  };

  outputs = { self, nixpkgs, vscode-server, ... }@inputs:
    let
      # Global Variables
      ## Define stateVersion (DO NOT MODIFY)
      stateVersion = "25.05";
      ## Define system architecture
      system = "x86_64-linux";
      # Global Functions
      ## Helper function for generating Virtual Server configurations
      createVS = 
        {
          modules ? [ ]
        }:
        nixpkgs.libs.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs;
          };
          modules = modules ++ [
            {
              # Inject stateVersion variable
              stateVersion = stateVersion;
            }
          ];
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