{
  description = "Reinitialized Infrastructure";

  inputs = {
    nixpkgsMaster.url = "github:NixOS/nixpkgs/master";
    nixpkgsUnstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgsStable.url = "github:NixOS/nixpkgs/nixos-26.05";
    # llm1's Strata build, held out of updates (docs/llm1.md, "Update policy").
    nixpkgsStrata.url = "github:NixOS/nixpkgs/c508844df6c28fa6dabc1b6af70f3ccbd65c5201";

    vscodeServer = {
      url = "github:nix-community/nixos-vscode-server";
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
          memory = 40960;
          cores = 12;
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

        # The GPU passthrough, NUMA binding and sizes are set by hand on hv1 after
        # restore (docs/llm1.md, "hv1 VM config").
        llm1 = library.makeDualExport "llm1" {
          system = "x86_64-linux";
          vmId = 210;
          enableProtection = true;
          memory = 106496;
          cores = 28;
          disks = [
            {
              storage = "hotData";
              size = 50;
            }
            {
              storage = "hotData";
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
            "${inputs.self}/modules/profiles/meshNetwork"
            "${inputs.self}/modules/profiles/mountData.nix"
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
        # gs1 = library.makeDualExport "gs1" {
        #   system = "x86_64-linux";
        #   vmId = 209;
        #   enableProtection = true;
        #   memory = 8192;
        #   disks = [
        #     {
        #       storage = "hotData";
        #       size = 20;
        #     }
        #     {
        #       storage = "coldData";
        #       size = 100;
        #     }
        #   ];
        #   networking = [
        #     {
        #       bridge = "vmbr0";
        #       firewall = false;
        #       vlan = 11;
        #     }
        #   ];
        #   modules = [
        #     inputs.vscodeServer.nixosModules.default
        #     "${inputs.self}/modules/profiles/containers"
        #     "${inputs.self}/modules/profiles/mountData.nix"
        #   ];
        # };
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

        llm1 = dualSystems.llm1.nixosSystem;

        db1 = dualSystems.db1.nixosSystem;
        #gs1 = dualSystems.gs1.nixosSystem;
      };

      # Pure validation uses checked-in synthetic metadata explicitly. Live
      # nixosConfigurations retain their external-only secret import behavior.
      checks.x86_64-linux = builtins.mapAttrs (
        host: _: dualSystems.${host}.validationSystem.config.system.build.toplevel
      ) inputs.self.nixosConfigurations;

      packages = library.forAllSystems (system: {
        # Reference VMA package from dual export
        devenv = dualSystems.devenv.package;

        rp1 = dualSystems.rp1.package;

        apps1 = dualSystems.apps1.package;
        apps2 = dualSystems.apps2.package;
        apps3 = dualSystems.apps3.package;

        llm1 = dualSystems.llm1.package;

        db1 = dualSystems.db1.package;
      });
    };
}
