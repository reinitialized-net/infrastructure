# hosts/apps1.nix
## Contains all essential reinitialized.net applications and services
{ ... }:
let
  huduEnv = import ../secrets/hudu.nix;
in
{
  imports = [
    ../hardware/qemu.nix
    ../modules/containers.nix
    ../modules/standard.nix
  ];
  # Network Configuration
  networking = {
    # Set Hostname
    hostName = "apps1";
    # Disable DHCP for static configuration (WILL OVERRIDE IF ENABLED)
    useDHCP = false;
    # Set Firewall rules
    firewall = {
      allowedTCPPorts = [ 80 ];
      allowedUDPPorts = [ 80 ];
    };
  };
  ## We use systemd-networkd for network configuration
  systemd.network.networks = {
    "eth0" = {
      address = [
        "10.1.11.2/24"
      ];
      dns = [ 
        "1.1.1.1" 
        "8.8.8.8" 
      ]; 
      gateway = [ 
        "10.1.11.1"
      ];
      matchConfig = {
        Path = "pci-0000:06:12.0";
      };
    };
  };
  #services.openssh.listenAddresses = [ ];

  # Hosted Services
  ## Docker-based Containers
  virtualisation.oci-containers.containers = {
    ## Hudu
    postgres1 = {
      autoStart = true;
      environment = huduEnv;
      image = "docker.io/library/postgres:18-alpine";
      networks = [ 
        "backend"
      ];
      volumes = [
        "postgres1_data:/var/lib/postgresql/data"
      ];
    };
    redis1 = {
      autoStart = true;
      cmd = [ "redis-server" ];
      environment = huduEnv;
      image = "docker.io/library/redis:8-alpine";
      networks = [ 
        "backend"
      ];
      volumes = [
        "redis1_data:/var/lib/redis/data"
      ];
    };
    hudu1 = {
      autoStart = true;
      dependsOn = [
        "postgres1"
        "redis1"
      ];
      environment = huduEnv;
      image = "hududocker/hudu:latest";
      networks = [ 
        "backend"
      ];
      ports = [ 
        "127.0.0.1:3000:3000"
      ];
      volumes = [
        "hudu_data:/var/www/hudu2/public/uploads/"
        "hudu_data:/var/www/hudu2/uploads"
        "hudu_data:/var/lib/app/data"
      ];
    };
    hudu2 = {
      autoStart = true;
      cmd = [ 
        "bundle" 
        "exec" 
        "sidekiq" 
        "-C" 
        "config/sidekiq.yml"
      ];
      dependsOn = [
        "postgres1"
        "redis1"
      ];
      environment = huduEnv;
      image = "hududocker/hudu:latest";
      networks = [ 
        "backend"
      ];
      volumes = [
        "hudu_data:/var/www/hudu2/public/uploads/"
        "hudu_data:/var/www/hudu2/uploads"
      ];
    };
  };
  ## NixOS-based Containers
  containers = {
    # technitium = {
    #   ephemeral = true;
    #   autoStart = true;
    #   privateNetwork =  false;

    #   bindMounts = {

    #   };

    #   config = { ... }: {
    #     services.technitium-dns-server = {
    #       enable = true;
          
    #     };
    #   };
    # };

    nginx = {
      ephemeral = true;
      autoStart = true;
      privateNetwork = false;

      bindMounts = {
        "/var/www/hudu2/config" = {
          hostPath = "/var/www/hudu2/config";
          isReadOnly =  false;
        };
      };
      config = { ... }: {
        # Setup Nginx service
        services.nginx = {
          enable = true;
          recommendedProxySettings = true;
          recommendedTlsSettings = true;

          virtualHosts = {
            "_" = {
              default = true;
              listen = [
                { 
                  addr = "0.0.0.0";
                  port = 80;
                }
              ];
              root = "/var/www/hudu2/public";
              locations = {
                # Deny access to dotfiles
                "/." = {
                  extraConfig = ''
                    deny all;
                  '';
                };
                # Deny access to .rb and .log files
                "~* ^.+\\.(rb|log)$" = {
                  extraConfig = ''
                    deny all;
                  '';
                };
                # WebSocket cable proxy
                "/cable" = {
                  proxyPass = "http://127.0.0.1:3000/cable";
                  proxyWebsockets = true;
                };
                # Try files, fallback to @rails
                "/" = {
                  tryFiles = "$uri @rails";
                };
                # Rails app fallback
                "@rails" = {
                  proxyPass = "http://127.0.0.1:3000";
                };
              };
            };
          };
        };
      };
    };
  };
}