{
  self,
  defaultStateVersion,
  pkgs,
  ...
}:{
  # Networking Configuration
  networking = {
    hostName = "rp1";
    useDHCP = false;
    firewall.whitelist = [
      {
        port = 80;
        protocol = "tcp_udp";
        ipType = "ipv4";
        source = [ "0.0.0.0/0" ];
      }
      {
        port = 443;
        protocol = "tcp_udp";
        ipType = "ipv4";
        source = [ "0.0.0.0/0" ];
      }
    ];
  };
  systemd.network.networks = {
    "eth0" = {
      address = [
        "10.1.12.2/29"
        #10.1.12.3/29
        "10.1.12.4/29"
      ];
      dns = [
        "10.1.12.3"
        #"10.1.11.2"
        #"10.1.11.3"
      ];
      gateway = [
        "10.1.12.1"
      ];
      matchConfig.Path = "pci-0000:06:12.0";
    };
  };
  # Configure MeshNetwork
  services.meshNetwork = {
    enable = true;
    nodeId = 2;
    dockerIntegration = false;
  };
  # Ensure container directories exist
  systemd.tmpfiles.rules = [
    "d /mnt/containers/nginx/var/lib/acme 0750 root root -"
  ];
  # Configure Nginx Reverse Proxy
  containers.nginx = {
    ephemeral = true;
    autoStart = true;
    privateNetwork = false;
    
    bindMounts = {
      "/var/lib/acme" = {
        hostPath = "/mnt/containers/nginx/var/lib/acme";
        isReadOnly = false;
      };
    };

    config = { lib, ... }: {
      system.stateVersion = lib.mkDefault defaultStateVersion;
      
      # Enable ACME for automatic SSL certificates
      security.acme = {
        acceptTerms = true;
        defaults = {
          email = "admin@reinitialized.net";
        };
      };
      # Nginx
      services.nginx = {
        enable = true;
        package = (pkgs.angie.override { withStream = true; });
        recommendedProxySettings = true;
        recommendedTlsSettings = true;

        virtualHosts = {
          "docs.reinitialized.net" = {
            forceSSL = true;
            enableACME = true;
            listenAddresses = [ 
              "10.1.12.4"
            ];

            locations."/" = {
              proxyPass = "http://10.255.0.3:3000";
            };
          };
          "media.reinitialized.me" = {
            forceSSL = true;
            enableACME = true;
            listenAddresses = [ 
              "10.1.12.4"
            ];
            
            locations."/" = {
              proxyPass = "http://10.255.0.3:3000";
            };
          };

          "one.dns.reinitialized.net" = {
            forceSSL = true;
            enableACME = true;
            listenAddresses = [ 
              "10.1.12.4"
            ];
            
            locations."/" = {
              proxyPass = "http://10.255.0.3:3000";
            };
          };
          "two.dns.reinitialized.net" = {
            forceSSL = true;
            enableACME = true;
            listenAddresses = [ 
              "10.1.12.4"
            ];
            
            locations."/" = {
              proxyPass = "http://10.255.0.3:3000";
            };
          };
        };
      };
    };
  };
}