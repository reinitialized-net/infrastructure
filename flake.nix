{
  description = "Official Bleu Pigger NixOS Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { 
        inherit system;
      };
      nixosSystem = nixpkgs.lib.nixosSystem;
    in
    {
      # packages.${system}.iso = nixosSystem {
      #   inherit system;
      #   modules = [ 
      #     ./nixos/demo.nix
      #   ];
      # }.config.system.build.isoImage;

      nixosConfigurations.standardVM = nixosSystem {
        specialArgs = { 
          inherit inputs;
        };
        modules = [
          ./nixos/hardware/qemu.nix
          ./nixos/profiles/standard.nix
        ];
      };
      nixosConfigurations.demoTesting = nixosSystem {
        specialArgs = { 
          inherit inputs;
        };
        modules = [
          ./nixos/hosts/demo.testing.nix
        ];
      };
    };
}

