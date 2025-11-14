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
      # Standard Configuration: Used for standing up new hosts
      nixosConfigurations.standard = makeConfig "standard" {};
      # devenv: NixOS-based Development Environment
      nixosConfigurations.devenv = makeConfig "devenv" {
        modules = [
          inputs.vscode-server.nixosModules.default
        ];
      };
      # rp1: Primary Reverse Proxy
      nixosConfigurations.rp1 = makeConfig "rp1" {};
      # apps1: Core Applications Host
      nixosConfigurations.apps1 = makeConfig "apps1" {};
      # apps2: Applications Host
      nixosConfigurations.apps2 = makeConfig "apps2" {};
    };
}