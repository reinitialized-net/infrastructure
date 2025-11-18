{
  description = "Reinitialized Infrastructure";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    vscode-server.url = "github:nix-community/nixos-vscode-server";
  };

  outputs = { nixpkgs, nixpkgs-unstable, ... }@inputs:
    let
      # Global Functions
      ## Import makeConfig
      makeConfig = import ./library/makeConfig.nix {
        inherit inputs nixpkgs nixpkgs-unstable;
      };
    in {
      # initOS: Used for standing up new hosts
      nixosConfigurations.initOS = makeConfig "initOS" {};
      # devenv: NixOS-based Development Environment
      nixosConfigurations.devenv = makeConfig "devenv" {
        modules = [
          inputs.vscode-server.nixosModules.default
          ./modules/containers.nix
        ];
      };
      # rp1: Primary Reverse Proxy
      nixosConfigurations.rp1 = makeConfig "rp1" {};
      # apps1: Core Applications Host
      nixosConfigurations.apps1 = makeConfig "apps1" {
        modules = [
          ./modules/containers.nix
        ];
      };
      # apps2: Applications Host
      nixosConfigurations.apps2 = makeConfig "apps2" {
        modules = [
          ./modules/containers.nix
        ];
      };
    };
}