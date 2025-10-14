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
          ./hardware/qemu.nix
          ./profiles/standard.nix
          {
            # Import baseline configuration
            imports = [
            ];
          }
        ];
      };
    };
}