{
  description = "Reinitialized Infrastructure";

  inputs = {
    nixpkgsMaster.url = "github:NixOS/nixpkgs/master";
    nixpkgsUnstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgsStable.url = "github:NixOS/nixpkgs/nixos-25.11";

    vscodeServer = {
      url = "github:nix-community/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgsStable";
    };
  };

  outputs =
    inputs:
    let
      library = import "${inputs.self}/library" {
        inherit (inputs) self;
      };
    in
    {
      nixosModules.default = {
        imports = [
          ./modules/profiles/firewall.nix
          ./modules/profiles/meshNetwork
          ./modules/profiles/secrets.nix
        ];
      };

      packages = library.forAllSystems (system:
      {
          standard = library.generateVMAImage "standard" {
            inherit system;

            vmId = 100;
            enableProtection = false;
            disks = [
              {
                storage = "hotData";
                size = 25;
              }
            ];
            networking = [
              {
                bridge = "vmbr0";
                firewall = false;
                vlan = 200;
                useDHCP = true;
              }
            ];
          };

          devenv = library.generateVMAImage "devenv" {
            inherit system;

            vmId = 203;
            enableProtection = true;
            disks = [
              {
                storage = "hotData";
                size = 20;
              }
              {
                storage = "coldData";
                size = 100;
              }
            ];
            networking = [
              {
                bridge = "vmbr0";
                firewall = false;
                vlan = 200;
                useDHCP = true;
              }
            ];

            modules = [
              inputs.vscodeServer.nixosModules.default
              "${inputs.self}/modules/profiles/mountData.nix"
              "${inputs.self}/modules/profiles/containers.nix"
            ];
          };
        }
      );
    };
}
