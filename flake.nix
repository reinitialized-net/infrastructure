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
      nixosConfigurations.devenv = createVS {
        modules = [
          ./hosts/devenv.nix
          inputs.vscode-server.nixosModules.default
        ];
      };
      nixosConfigurations.rp1 = createVS {
        modules = [
          ./hosts/rp1.nix
        ];
      };
    };
}