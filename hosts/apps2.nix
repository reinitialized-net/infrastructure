# hosts/apps1.nix
## Contains all essential reinitialized.net applications and services
{ stateVersion, lib, ... }:
{
  imports = [
    ../hardware/qemu.nix
  ];
  # Network Configuration
  networking = {
    # Set Hostname
    hostName = "apps1";
    # Disable DHCP for static configusration (WILL OVERRIDE IF ENABLED)
    useDHCP = false;
    # Set Firewall rules
    firewall = {
      allowedTCPPorts = [ 
        80
        53
        5380
      ];
      allowedUDPPorts = [ 
        80 
        53
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