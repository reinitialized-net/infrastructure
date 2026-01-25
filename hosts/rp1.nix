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
    firewall.denylist = [
      {
        port = 53;
        protocol = "tcp_udp";
        ipType = "ipv4";
        source = [
          "10.0.0.0/8"
          "172.16.0.0/24"
          "192.168.0.0/16"
        ];
      }
      {
        port = 853;
        protocol = "tcp_udp";
        ipType = "ipv4";
        source = [
          "10.0.0.0/8"
          "172.16.0.0/24"
          "192.168.0.0/16"
        ];
      }
    ];
    firewall.allowlist = [
      {
        port = 80;
        protocol = "tcp_udp";
        ipType = "ipv4";
        source = [
          "0.0.0.0/0"
        ];
      }
      {
        port = 443;
        protocol = "tcp_udp";
        ipType = "ipv4";
        source = [
          "0.0.0.0/0"
        ];
      }
      {
        port = 53;
        protocol = "tcp_udp";
        ipType = "ipv4";
        source = [
          "0.0.0.0/0"
        ];
      }
      {
        port = 853;
        protocol = "tcp_udp";
        ipType = "ipv4";
        source = [
          "0.0.0.0/0"
        ];
      }
    ];
  };
  systemd.network.networks = {
    "eth0" = {
      address = [
        "10.1.12.2/29"
        "10.1.12.3/29"
        "10.1.12.4/29"
      ];
      dns = [
        "10.1.11.2"
        "10.1.11.3"
      ];
      ntp = [
        "10.1.200.1"
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
      
      # Ensure nginx user can access ACME files
      users.users.nginx = {
        extraGroups = [ "acme" ];
      };
      
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

        # Stream configuration for DNS
        streamConfig = ''
          upstream dnsOne {
            server 10.1.11.2:53;
            server 10.1.11.2:853;
          }
          upstream dnsTwo {
            server 10.1.11.2:53;
            server 10.1.11.2:853;
          }
          
          server {
            listen 10.1.12.2:53 udp;
            listen 10.1.12.2:53;
            listen 10.1.12.2:853;
            listen 10.1.12.2:853 udp;
            proxy_pass dnsOne;
            proxy_timeout 1s;
            proxy_responses 1;
          }
          server {
            listen 10.1.12.3:53 udp;
            listen 10.1.12.3:53;
            listen 10.1.12.3:853;
            listen 10.1.12.3:853 udp;
            proxy_pass dnsTwo;
            proxy_timeout 1s;
            proxy_responses 1;
          }
        '';

        virtualHosts = {
          "docs.reinitialized.net" = {
            forceSSL = true;
            enableACME = true;
            listenAddresses = [ 
              "10.1.12.4"
            ];

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
                proxyPass = "http://10.255.0.3:3000/cable";
                proxyWebsockets = true;
              };
              # Main proxy with Rails-specific settings
              "/" = {
                extraConfig = ''
                  client_body_buffer_size 128k;
                  proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;
                  send_timeout 5m;
                  proxy_read_timeout 240;
                  proxy_send_timeout 240;
                  proxy_connect_timeout 240;
                  proxy_set_header Host $host;
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                  proxy_set_header X-Forwarded-Host $host;
                  proxy_set_header X-Forwarded-Proto $scheme;
                  proxy_redirect  http://  $scheme://;
                  proxy_http_version 1.1;
                  proxy_set_header Connection "";
                  proxy_cache_bypass $cookie_session;
                  proxy_no_cache $cookie_session;
                  proxy_buffers 32 4k;
                  proxy_headers_hash_bucket_size 128;
                  proxy_headers_hash_max_size 1024;
                  proxy_pass http://10.255.0.3:3000;
                '';
              };
            };
          };
          "media.reinitialized.me" = {
            forceSSL = true;
            enableACME = true;
            listenAddresses = [ 
              "10.1.12.4"
            ];
            
            locations."/" = {
              proxyPass = "http://10.1.11.21:8096";
            };
          };

          "one.dns.reinitialized.net" = {
            forceSSL = true;
            enableACME = true;
            listenAddresses = [ 
              "10.1.12.2"
            ];
            
            locations."/" = {
              proxyPass = "http://10.255.0.3:5380";
            };
          };
          "two.dns.reinitialized.net" = {
            forceSSL = true;
            enableACME = true;
            listenAddresses = [ 
              "10.1.12.3"
            ];
            
            locations."/" = {
              proxyPass = "http://10.255.0.4:5380";
            };
          };
        };
      };
    };
  };
}