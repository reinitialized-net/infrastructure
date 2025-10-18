{
  description = "Reinitialized Infrastructure";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    vscode-server.url = "github:nix-community/nixos-vscode-server";
  };

  outputs = { self, nixpkgs, localPackages, vscode-server, ... }@inputs:
    let
      system = "x86_64-linux";
      # pkgs = import nixpkgs { 
      #   inherit system;
      # };
      nixosSystem = nixpkgs.lib.nixosSystem;

      createVS = 
        {
          modules ? [ ]
        }:
        nixosSystem {
          inherit system;

          specialArgs = {
            inherit inputs;
            inherit localPackages;
          };

          modules = modules;
        };
    in {
      nixosConfigurations.devenv = createVS {
        modules = [
          ./hardware/qemu.nix
          ./modules/standard.nix
          ./hosts/devenv.nix

          inputs.vscode-server.nixosModules.default
        ];
      };
    };
}