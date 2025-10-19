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

  # Setup Caddy container
  containers.caddy = {
    autoStart = true;
    privateNetwork = false;
    bindMounts = {
      "/var/lib/caddy" = {
        hostPath = "/mnt/containers/caddy/var/lib/caddy";
        isReadOnly =  false;
      };
      "/etc/caddy" = {
        hostPath = "/mnt/containers/caddy/etc/caddy";
        isReadOnly = false;
      };
    };

    config = { ... }: {
      # Enable Caddy service
      services.caddy = {
        enable = true;

        virtualHosts = {
          "jellyfin.reinitialized.me" = {
            serverAliases = [ "www.jellyfin.reinitialized.me" ];
            listenAddresses = [ "10.1.12.2" ];
            hostName = "media1.svcs.reinitialized.net";

            extraConfig = ''
              reverse_proxy http://10.1.11.21:8096
            '';
          };
        };
      };
    };
  };
}