# hosts/apps1.nix
## Contains all essential reinitialized.net applications and services
{ defaultStateVersion, lib, pkgsUnstable, ...}: 
let
  huduEnv = import ../secrets/hudu.nix;
in
{
  # Network Configuration
  networking = {
    # Set Hostname
    hostName = "apps1";
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
          "0.0.0.0/0" 
        ];
      }
      # Allow HTTP
      {
        port = 80;
        protocol = "tcp_udp";
        ipType = "ipv4";
        source = [ 
          "10.1.12.2/29"
        ];
      }
      # Allow Technitium DNS WebUI
      {
        port = 5380;
        protocol = "tcp";
        ipType = "ipv4";
        source = [ 
          "10.1.12.2/29"
        ];
      }
      # Allow Technitium DNS WebUI Secure for Clustering
      {
        port = 53443;
        protocol = "tcp";
        ipType = "ipv4";
        source = [ 
          "10.1.11.3/24"
        ];
      }
    ];
  };
  ## We use systemd-networkd for network configuration
  systemd.network.networks = {
    "eth0" = {
      address = [
        "10.1.11.2/24"
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
  # Hosted Services
  ## Docker-based Containers
  virtualisation.oci-containers.containers = {
    ## Hudu
    postgres1 = {
      autoStart = true;
      environment = huduEnv;
      image = "docker.io/library/postgres:18-alpine";
      networks = [ 
        "backend"
      ];
      volumes = [
        "postgres1_data:/var/lib/postgresql/data"
      ];
    };
    redis1 = {
      autoStart = true;
      cmd = [ "redis-server" ];
      environment = huduEnv;
      image = "docker.io/library/redis:8-alpine";
      networks = [ 
        "backend"
      ];
      volumes = [
        "redis1_data:/var/lib/redis/data"
      ];
    };
    hudu1 = {
      autoStart = true;
      dependsOn = [
        "postgres1"
        "redis1"
      ];
      environment = huduEnv;
      image = "hududocker/hudu:latest";
      networks = [ 
        "backend"
      ];
      ports = [ 
        "127.0.0.1:3000:3000"
      ];
      volumes = [
        "hudu_data:/var/www/hudu2/public/uploads/"
        "hudu_data:/var/www/hudu2/uploads"
        "hudu_data:/var/lib/app/data"
      ];
    };
    hudu2 = {
      autoStart = true;
      cmd = [ 
        "bundle" 
        "exec" 
        "sidekiq" 
        "-C" 
        "config/sidekiq.yml"
      ];
      dependsOn = [
        "postgres1"
        "redis1"
      ];
      environment = huduEnv;
      image = "hududocker/hudu:latest";
      networks = [ 
        "backend"
      ];
      volumes = [
        "hudu_data:/var/www/hudu2/public/uploads/"
        "hudu_data:/var/www/hudu2/uploads"
      ];
    };
  };
  ## NixOS-based Containers
  ### Create required folders
  systemd.tmpfiles.rules = [
    "d /mnt/data/nix/nginx1 0755 root root - -"
    "d /mnt/data/nix/technitium1 0755 root root - -"
  ];
  ### Container Configuration
  containers = {
    # Nginx for Hudu
    nginx1 = {
      ephemeral = true;
      autoStart = true;
      privateNetwork = false;

      bindMounts = {
        "/var/www/hudu2/config" = {
          hostPath = "/mnt/data/nix/nginx1";
          isReadOnly =  false;
        };
      };
      config = { ... }: {
        # Let host handle firewall
        networking.firewall.enable = false;
        # Set Container StateVersion (DO NOT TOUCH)
        system.stateVersion = defaultStateVersion;
        # Configure Nginx service
        services.nginx = {
          enable = true;
          recommendedProxySettings = true;
          recommendedTlsSettings = true;

          virtualHosts = {
            "_" = {
              default = true;
              listen = [
                { 
                  addr = "0.0.0.0";
                  port = 80;
                }
              ];
              root = "/var/www/hudu2/public";
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
                  proxyPass = "http://127.0.0.1:3000/cable";
                  proxyWebsockets = true;
                };
                # Try files, fallback to @rails
                "/" = {
                  tryFiles = "$uri @rails";
                };
                # Rails app fallback
                "@rails" = {
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
                    proxy_set_header X-Forwarded-Ssl off;
                    proxy_redirect  http://  $scheme://;
                    proxy_http_version 1.1;
                    proxy_set_header Connection "";
                    proxy_cache_bypass $cookie_session;
                    proxy_no_cache $cookie_session;
                    proxy_buffers 32 4k;
                    proxy_headers_hash_bucket_size 128;
                    proxy_headers_hash_max_size 1024;
                    proxy_pass http://127.0.0.1:3000;
                  '';
                };
              };
            };
          };
        };
      };
    };
    # Technitium DNS
    technitium1 = {
      ephemeral = true;
      autoStart = true;
      privateNetwork =  false;

      bindMounts = {
        "/var/lib/technitium-dns-server" = {
          hostPath = "/mnt/data/nix/technitium1";
          isReadOnly =  false;
        };
      };

      config = { ... }: {
        # Let host handle firewall
        networking.firewall.enable = true;
        # Set container StateVersion (DO NOT TOUCH)
        system.stateVersion = defaultStateVersion;
        services.technitium-dns-server = {
          # Enable Technitium DNS Server
          enable = true;
          # Set package to unstable for newer version
          package = pkgsUnstable.technitium-dns-server;
        };
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