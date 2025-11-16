# hosts/apps1.nix
## Contains all essential reinitialized.net applications and services
{ defaultStateVersion, lib, ... }:
{
  # Network Configuration
  networking = {
    # Set Hostname
    hostName = "apps2";
    # Disable DHCP for static configusration (WILL OVERRIDE IF ENABLED)
    useDHCP = false;
    # Set Firewall rules
    firewall = {
      whitelist = [
        # # Allow DNS
        # {
        #   port = 53;
        #   protocol = "tcp_udp";
        #   ipType = "ipv4";
        #   source = [ "10.1.11.0/24" ];
        # }
      ];
    };
  };
  ## We use systemd-networkd for network configuration
  systemd = {
    network = {
      networks = {
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
    };
  };
}