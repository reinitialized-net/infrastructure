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
          enableProtection = false;
          vmId = 100;
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
            }
          ];
        };

        devenv = library.makeDualExport "devenv" {
          system = "x86_64-linux";
          enableProtection = true;
          vmId = 202;
          memory = 65536;
          cores = 6;
          disks = [
            { 
              storage = "hotData";
              size = 250; 
            }
            { 
              storage = "coldData";
              size = 250;
            }
          ];
          networking = [
            { 
              bridge = "vmbr0";
              firewall = false;
              vlan = 200;
            }
          ];
          modules = [
            inputs.vscodeServer.nixosModules.default
            "${inputs.self}/modules/profiles/containers"
            "${inputs.self}/modules/profiles/mountData.nix"
          ];
        };
        rp1 = library.makeDualExport "rp1" {
          system = "x86_64-linux";
          enableProtection = true;
          vmId = 203;
          disks = [
            { 
              storage = "hotData";
              size = 20; 
            }
            { 
              storage = "coldData";
              size = 50;
            }
          ];
          networking = [
            { 
              bridge = "vmbr0";
              firewall = false;
              vlan = 12;
            }
          ];
          modules = [
            inputs.vscodeServer.nixosModules.default
            "${inputs.self}/modules/profiles/containers"
            "${inputs.self}/modules/profiles/mountData.nix"
          ];
        };

        apps1 = library.makeDualExport "apps1" {
          system = "x86_64-linux";
          vmId = 204;
          enableProtection = true;
          memory = 8192;
          disks = [
            { 
              storage = "hotData";
              size = 20; 
            }
            { 
              storage = "coldData";
              size = 50;
            }
          ];
          networking = [
            { 
              bridge = "vmbr0";
              firewall = false;
              vlan = 11;
            }
          ];
          modules = [
            inputs.vscodeServer.nixosModules.default
            "${inputs.self}/modules/profiles/containers"
            "${inputs.self}/modules/profiles/mountData.nix"
          ];
        };
        apps2 = library.makeDualExport "apps2" {
          system = "x86_64-linux";
          vmId = 205;
          enableProtection = true;
          memory = 8192;
          disks = [
            { 
              storage = "hotData";
              size = 20; 
            }
            { 
              storage = "coldData";
              size = 150;
            }
          ];
          networking = [
            { 
              bridge = "vmbr0";
              firewall = false;
              vlan = 11;
            }
          ];
          modules = [
            inputs.vscodeServer.nixosModules.default
            "${inputs.self}/modules/profiles/containers"
            "${inputs.self}/modules/profiles/mountData.nix"
          ];
        };
        apps3 = library.makeDualExport "apps3" {
          system = "x86_64-linux";
          vmId = 207;
          enableProtection = true;
          memory = 8192;
          disks = [
            { 
              storage = "hotData";
              size = 20; 
            }
            { 
              storage = "coldData";
              size = 25;
            }
          ];
          networking = [
            { 
              bridge = "vmbr0";
              firewall = false;
              vlan = 11;
            }
          ];
          modules = [
            inputs.vscodeServer.nixosModules.default
            "${inputs.self}/modules/profiles/containers"
            "${inputs.self}/modules/profiles/mountData.nix"
          ];
        };

        ai1 = library.makeDualExport "ai1" {
          system = "x86_64-linux";
          vmId = 208;
          enableProtection = true;
          memory = 8192;
          disks = [
            { 
              storage = "hotData";
              size = 20; 
            }
            { 
              storage = "hotData"; # Using hotData for both disks to optimize for performance of the models
              size = 20;
            }
          ];
          networking = [
            { 
              bridge = "vmbr0";
              firewall = false;
              vlan = 11;
            }
          ];
          modules = [
            inputs.vscodeServer.nixosModules.default
            "${inputs.self}/modules/profiles/mountData.nix"
            "${inputs.self}/modules/profiles/meshNetwork"
          ];
        };

        db1 = library.makeDualExport "db1" {
          system = "x86_64-linux";
          vmId = 206;
          enableProtection = true;
          memory = 8192;
          disks = [
            { 
              storage = "hotData";
              size = 20; 
            }
            { 
              storage = "hotData"; # Using hotData for both disks to optimize for performance of the databases
              size = 20;
            }
          ];
          networking = [
            { 
              bridge = "vmbr0";
              firewall = false;
              vlan = 11;
            }
          ];
          modules = [
            inputs.vscodeServer.nixosModules.default
            "${inputs.self}/modules/profiles/containers"
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

        rp1 = dualSystems.rp1.nixosSystem;

        apps1 = dualSystems.apps1.nixosSystem;
        apps2 = dualSystems.apps2.nixosSystem;
        apps3 = dualSystems.apps3.nixosSystem;

        ai1 = dualSystems.ai1.nixosSystem;

        db1 = dualSystems.db1.nixosSystem;
        #gs1 = dualSystems.gs1.nixosSystem;
      };
      packages = library.forAllSystems (system:
        {
            # Reference VMA package from dual export
            devenv = dualSystems.devenv.package;
            
            rp1 = dualSystems.rp1.package;

            apps1 = dualSystems.apps1.package;
            apps2 = dualSystems.apps2.package;
            apps3 = dualSystems.apps3.package;

            ai1 = dualSystems.ai1.package;
            
            db1 = dualSystems.db1.package;
        }
      );
    };
}
