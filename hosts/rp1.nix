# hosts/rp1.nix
## 
{ ... }:
{
  imports = [
    ../hardware/qemu.nix
    ../modules/standard.nix
  ];

  # System-specific configuration
  networking = {
    hostName = "rp1";
    interfaces.eth0.ipv4.addresses = [
      {
        address = "10.1.12.2";
        prefixLength = 29;
      }
      {
        address = "10.1.12.3";
        prefixLength = 29;
      }
      {
        address = "10.1.12.4";
        prefixLength = 29;
      }
    ];
    defaultGateway = "10.1.12.1";
    nameservers = [ 
      "1.1.1.1"
      "8.8.8.8" 
    ];
    firewall.allowedTCPPorts = [ 80 443 ];
    firewall.allowedUDPPorts = [ 80 443 ];
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