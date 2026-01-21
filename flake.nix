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
        }
      );
    };
}
