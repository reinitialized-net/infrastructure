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
    in {
      nixosConfigurations.devenv = nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
        };

        modules = [
          vscode-server.nixosModules.default
          ./hosts/devenv.nix
        ];
      };
    };
}