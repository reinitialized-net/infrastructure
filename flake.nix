{
  description = "Reinitialized Infrastructure";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    vscode-server.url = "github:nix-community/nixos-vscode-server";
  };

  outputs = { nixpkgs, ... }@inputs:
    let
      # Global Functions
      ## Import makeConfig
      makeConfig = import ./lib/makeConfig.nix { 
        inherit nixpkgs inputs;
      };
    in {
      # initOS: Used for standing up new hosts
      nixosConfigurations.initOS = makeConfig "initOS" {};
      # devenv: NixOS-based Development Environment
      nixosConfigurations.devenv = makeConfig "devenv" {
        modules = [
          inputs.vscode-server.nixosModules.default

          ./extensions/firewall.nix
          ./modules/containers.nix
        ];
      };
      # rp1: Primary Reverse Proxy
      nixosConfigurations.rp1 = makeConfig "rp1" {
        modules = [
          ./extensions/firewall.nix
          ./modules/containers.nix
        ];
      };
      # apps1: Core Applications Host
      nixosConfigurations.apps1 = makeConfig "apps1" {
        modules = [
          ./extensions/firewall.nix
          ./modules/containers.nix
        ];
      };
      # apps2: Applications Host
      nixosConfigurations.apps2 = makeConfig "apps2" {
        modules = [
          ./extensions/firewall.nix
          ./modules/containers.nix
        ];
      };

      # Expose extensions for nixd auto-complete
      ## extensions/firewall.nix
      nixosModules.firewall = ./extensions/firewall.nix;
    };
}