# hosts/rp1.nix
## Handles reverse proxy service in an isolated environment.
{ ... }:
{
  imports = [
    ../hardware/qemu.nix
    ../modules/standard.nix
  ];
  # Network Configuration
  networking = {
    # Set Hostname
    hostName = "rp1";
    # Disable DHCP for static configuration (WILL OVERRIDE IF ENABLED)
    useDHCP = false;
    # Set Firewall rules
    firewall = {
      allowedTCPPorts = [ 80 443 ];
      allowedUDPPorts = [ 80 443 ];
    };
  };
  systemd.network.networks = {
    "eth0" = {
      address = [
        "10.1.12.2/29"
        "10.1.12.3/29"
        "10.1.12.4/29"
      ];
      dns = [ 
        "1.1.1.1" 
        "8.8.8.8" 
      ];
      gateway = [
        "10.1.12.1"
      ];
      matchConfig = {
        Path = "pci-0000:06:12.0";
      };
      # routes = [
      #   {
      #     Gateway = "10.1.12.1";
      #     PreferredSource = "10.1.12.2";
      #   }
      # ];
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
                proxyPass = "http://10.1.11.2:80"; 
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