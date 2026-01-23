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
      
      # Define dual-export systems once - call makeDualExport once per system
      dualSystems = {
        standard = {
          system = "x86_64-linux";
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
        devenv = library.makeDualExport "devenv" {
          system = "x86_64-linux";
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
            "${inputs.self}/modules/profiles/containers.nix"
            "${inputs.self}/modules/profiles/mountData.nix"
          ];
        };
      };
    in
    {
      nixosModules.default = {
        imports = [
          "${inputs.self}/modules/profiles/firewall.nix"
          "${inputs.self}/modules/profiles/meshNetwork"
          "${inputs.self}/modules/profiles/secrets.nix"
        ];
      };

      # Helper to define systems that can export both VMA packages and nixosConfigurations
      # Usage: Define systems once in dualSystems, then reference both outputs
      nixosConfigurations = {
        # Reference nixosSystem from dual export
        devenv = dualSystems.devenv.nixosSystem;
      };

      packages = library.forAllSystems (system:
      {
          # Reference VMA package from dual export
          devenv = dualSystems.devenv.package;
        }
      );
    };
}
