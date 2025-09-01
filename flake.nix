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
      packages.${system}.iso = nixosSystem {
        inherit system;
        modules = [ 
          ./demo.nix
        ];
      }.config.system.build.isoImage;

      nixosConfigurations.nixos-demo = nixosSystem {
        inherit system;
        modules = [
          ./demo.nix
        ];
      };
    };
}
