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
      nixosConfiguration.devenv = nixosSystem {
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
            ];
          }
        ]
      };
    }
};