# hosts/rp1.nix
## Handles reverse proxy service in an isolated environment.
{ ... }:
{
  imports = [
    ../hardware/qemu.nix
    ../modules/standard.nix
  ];

  # System-specific configuration
  networking = {
    hostName = "rp1";
    
    firewall = {
      allowedTCPPorts = [ 80 443 ];
      allowedUDPPorts = [ 80 443 ];
    };
  };
  systemd.network.networks = {
    "10-eth0" = {
      matchConfig = {
        Name = "eth0";
      };
      address = [
        "10.1.12.2/29"
        "10.1.12.3/29"
        "10.1.12.4/29"
      ];
      routes = [
        {
          Gateway = "10.1.12.1";
          PreferredSource = "10.1.12.2";
        }
      ];
      dns = [ 
        "1.1.1.1" 
        "8.8.8.8" 
      ];
    };
  };

  # Setup Nginx container
  containers.nginx = {
    ephemeral = true;
    autoStart = true;
    privateNetwork = false;

    bindMounts = {
      "/var/lib/acme" = {
        hostPath = "/mnt/containers/nginx/var/lib/acme";
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
          "media.reinitialized.me" = {
            enableACME = true;
            forceSSL = true;
            listenAddresses = [ "10.1.12.2" ];

            locations = {
              "/" = {
                proxyPass = "http://10.1.11.21:8096";
              };
            };
          };
          "riven.media.reinitialized.me" = {
            enableACME = true;
            forceSSL = true;
            listenAddresses = [ "10.1.12.2" ];

            locations = {
              "/" = {
                proxyPass = "http://10.1.11.21:3000";
              };
            };
          };

          "docs.reinitialized.net" = {
            enableACME = true;
            forceSSL = true;
            listenAddresses = [ "10.1.12.2" ];

            locations = {
              "/" = {
                proxyPass = "http://10.1.11.21:3000"; 
              };
            };
          };
        };
      };
      # Setup ACME
      security.acme = {
        acceptTerms = true;

        defaults = {
          email = "admin@reinitialized.net";
        };
      };
    };
  };
}