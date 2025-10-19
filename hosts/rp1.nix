# hosts/rp1.nix
## 
{ pkgs, ...}:
{
  imports = [
    ../hardware/qemu.nix
    
    ../modules/standard.nix
  ];

  # System-specific configuration
  networking.hostName = "devenv";
  networking.interfaces.eth0.ipv4.addresses = [
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
  networking.defaultGateway = "10.1.12.1";
  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];

  # Setup Caddy container
  containers.caddy = {
    autoStart = true;
    privateNetwork = false;
    bindMounts = {
      "/var/lib/caddy" = {
        hostPath = "/var/lib/caddy";
      };
      "/etc/caddy" = {
        hostPath = "/etc/caddy";
      };
    };

    config = { ... }: {
      # Mount persistant storage
      fileSystems = {
        "/var/lib/caddy" = {
          device = "/var/lib/caddy";
          fsType = "ext4";
        };
      };
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