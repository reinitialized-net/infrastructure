# hosts/apps1.nix
## Contains all essential reinitialized.net applications and services
{ defaultStateVersion, lib, ... }:
{
  # Network Configuration
  networking = {
    # Set Hostname
    hostName = "apps2";
    # Disable DHCP for static configuration (WILL OVERRIDE IF ENABLED)
    useDHCP = false;
    # Set Firewall rules
    firewall.whitelist = [
      # Allow DNS
      {
        port = 53;
        protocol = "tcp_udp";
        ipType = "ipv4";
        source = [ 
          "10.1.0.0/16"
          "192.168.11.0/24"
          "172.16.0.0/24"
        ];
      }
      # Allow Technitium DNS WebUI
      {
        port = 5380;
        protocol = "tcp";
        ipType = "ipv4";
        source = [ 
          "10.1.0.0/16"
          "192.168.11.0/24"
          "172.16.0.0/24"
        ];
      }
    ];
  };
  ## We use systemd-networkd for network configuration
  systemd.network.networks = {
    "eth0" = {
      address = [
        "10.1.11.3/24"
      ];
      dns = [ 
        "127.0.0.1"
        "10.1.11.3" 
      ]; 
      gateway = [ 
        "10.1.11.1"
      ];
      matchConfig = {
        Path = "pci-0000:06:12.0";
      };
    };
  };
  ## NixOS Containers
  ### Create required folders
  systemd.tmpfiles.rules = [
    "d /mnt/data/nix/technitium2 0755 root root - -"
  ];
  ### Define Container configuration
  containers = {
    # Technitium DNS
    technitium2 = {
      ephemeral = true;
      autoStart = true;
      privateNetwork =  false;

      bindMounts = {
        "/var/lib/technitium-dns-server" = {
          hostPath = "/mnt/data/nix/technitium2";
          isReadOnly =  false;
        };
      };

      config = { ... }: {
        # Let host handle firewall
        networking.firewall.enable = false;
        # Set Container StateVersion (DO NOT TOUCH)
        system.stateVersion = defaultStateVersion;
        # Enable Technitium DNS Server
        services.technitium-dns-server.enable = true;
        # Adjust systemd service to prevent DynamicUser permission issues (TODO: look into proper fix)
        systemd.services.technitium-dns-server.serviceConfig = {
          # Turn off DynamicUser to resolve permission issues
          DynamicUser = lib.mkForce false;
          # Create state directory for Technitium DNS server
          StateDirectory = "technitium-dns-server";
        };
      };
    };
  };
}