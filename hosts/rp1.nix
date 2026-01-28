{
  self,
  config,
  defaultStateVersion,
  pkgs,
  lib,
  ...
}:let
  internalOnly = ''
    allow 10.0.0.0/8;
    allow 172.16.0.0/12;
    allow 192.168.0.0/16;
    deny all;
  '';
in {
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
        exclude = [
          "10.1.11.2"
          "10.1.11.3"
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
        exclude = [
          "10.1.11.2"
          "10.1.11.3"
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
      {
        port = 53443;
        protocol = "tcp";
        ipType = "ipv4";
        source = [
          "10.0.0.0/8"
          "172.16.0.0/24"
          "192.168.0.0/16"
        ];
      }
      {
        port = 8443;
        protocol = "tcp";
        ipType = "ipv4";
        source = [
          "10.0.0.0/8"
          "172.16.0.0/24"
          "192.168.0.0/16"
        ];
      }
      {
        port = 8080;
        protocol = "tcp";
        ipType = "ipv4";
        source = [
          "10.0.0.0/8"
          "172.16.0.0/24"
          "192.168.0.0/16"
        ];
      }
      {
        port = 3478;
        protocol = "udp";
        ipType = "ipv4";
        source = [
          "10.0.0.0/8"
          "172.16.0.0/24"
          "192.168.0.0/16"
        ];
      }
      {
        port = 10001;
        protocol = "udp";
        ipType = "ipv4";
        source = [
          "10.1.11.0/24"
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
    "d /mnt/containers/dns-certs 0750 root root -"
    "d /run/dns-cert-trigger 0755 root root -"
  ];

  # Path watcher to trigger certificate distribution when container signals renewal
  systemd.paths.dns-cert-distribute = {
    description = "Watch for DNS certificate renewal trigger";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathModified = "/run/dns-cert-trigger/distribute-certs";
      Unit = "dns-cert-distribute.service";
    };
  };

  # Certificate distribution service - pushes PKCS#12 certs to DNS nodes via mesh
  systemd.services.dns-cert-distribute = {
    description = "Distribute DNS certificates to Technitium cluster nodes";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [ openssh rsync openssl coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      # Allow some time for ACME to finish writing files
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
      # Runtime directory for temp key with correct permissions
      RuntimeDirectory = "dns-cert-distribute";
      RuntimeDirectoryMode = "0700";
    };
    script = let
      sshKeyFile = config.secrets.certDistribution.file;
    in ''
      set -euo pipefail
      
      CERT_STAGING="/mnt/containers/dns-certs"
      
      # Copy SSH key to runtime dir with correct permissions (600)
      # This is needed because keys in nix store are 444 which SSH rejects
      SSH_KEY_TEMP="/run/dns-cert-distribute/ssh_key"
      cp "${sshKeyFile}" "$SSH_KEY_TEMP"
      chmod 600 "$SSH_KEY_TEMP"
      
      SSH_OPTS="-i $SSH_KEY_TEMP -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"
      
      # Function to convert and distribute certificate
      distribute_cert() {
        local DOMAIN="$1"
        local TARGET_HOST="$2"
        local CONTAINER_NAME="$3"
        
        local ACME_DIR="/mnt/containers/nginx/var/lib/acme/$DOMAIN"
        local PFX_FILE="$CERT_STAGING/$DOMAIN.pfx"
        
        if [[ ! -f "$ACME_DIR/fullchain.pem" ]] || [[ ! -f "$ACME_DIR/key.pem" ]]; then
          echo "Certificate files not found for $DOMAIN, skipping..."
          return 1
        fi
        
        echo "Converting $DOMAIN certificate to PKCS#12..."
        ${pkgs.openssl}/bin/openssl pkcs12 -export -legacy \
          -out "$PFX_FILE" \
          -inkey "$ACME_DIR/key.pem" \
          -in "$ACME_DIR/fullchain.pem" \
          -passout pass:
        
        chmod 640 "$PFX_FILE"
        
        echo "Distributing certificate to $TARGET_HOST..."
        ${pkgs.rsync}/bin/rsync -avz -e "ssh $SSH_OPTS" \
          "$PFX_FILE" \
          "certdist@$TARGET_HOST:/var/lib/acme/$DOMAIN/cert.pfx"
        
        echo "Restarting $CONTAINER_NAME on $TARGET_HOST..."
        ${pkgs.openssh}/bin/ssh $SSH_OPTS "certdist@$TARGET_HOST" \
          "sudo /run/current-system/sw/bin/docker restart $CONTAINER_NAME" || true
        
        echo "Successfully distributed certificate for $DOMAIN"
      }
      
      # Distribute to apps1 (dnsOne) via mesh IP
      distribute_cert "one.dns.reinitialized.net" "10.255.0.3" "dnsOne" || true
      
      # Distribute to apps2 (dnsTwo) via mesh IP
      distribute_cert "two.dns.reinitialized.net" "10.255.0.4" "dnsTwo" || true
      
      echo "Certificate distribution complete"
    '';
  };

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
      # Bind mount for triggering host certificate distribution
      "/run/host-trigger" = {
        hostPath = "/run/dns-cert-trigger";
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
        # Configure postRun hooks for DNS certificates
        certs."one.dns.reinitialized.net" = {
          postRun = ''
            touch /run/host-trigger/distribute-certs
          '';
        };
        certs."two.dns.reinitialized.net" = {
          postRun = ''
            touch /run/host-trigger/distribute-certs
          '';
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
          ## Upstream
          upstream dnsOneUI {
            server 10.255.0.3:53443;
          }
          upstream dnsOneService {
            server 10.1.11.2:53;
          }
          upstream dnsTwoUI {
            server 10.255.0.4:53443;
          }
          upstream dnsTwoService {
            server 10.1.11.3:53;
          }

          upstream unifiWeb {
            server 10.255.0.4:8443;
          }
          upstream unifiComm {
            server 10.255.0.4:8080;
          }
          upstream unifiStun {
            server 10.255.0.4:3478;
          }
          upstream unifiDiscovery {
            server 10.255.0.4:10001;
          }

          ## Listeners
          server {
            listen 10.1.12.2:53 udp;
            listen 10.1.12.2:53;
            proxy_pass dnsOneService;
            proxy_timeout 1s;
            proxy_responses 1;
          }
          server {
            listen 10.1.12.2:53443;
            proxy_pass dnsOneUI;
          }
          server {
            listen 10.1.12.3:53 udp;
            listen 10.1.12.3:53;
            proxy_pass dnsTwoService;
            proxy_timeout 1s;
            proxy_responses 1;
          }
          server {
            listen 10.1.12.3:53443;
            proxy_pass dnsTwoUI;
          }

          server {
            listen 10.1.12.4:8443;
            proxy_pass unifiWeb;
          }
          server {
            listen 10.1.12.4:8080;
            proxy_pass unifiComm;
          }
          server {
            listen 10.1.12.4:3478 udp;
            proxy_pass unifiStun;
          }
          server {
            listen 10.1.12.4:10001 udp;
            proxy_pass unifiDiscovery;
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
              proxyPass = "https://10.255.0.3:53443";
              extraConfig = internalOnly;
            };
          };
          "two.dns.reinitialized.net" = {
            forceSSL = true;
            enableACME = true;
            listenAddresses = [ 
              "10.1.12.3"
            ];
            
            locations."/" = {
              proxyPass = "https://10.255.0.4:53443";
              extraConfig = internalOnly;
            };
          };

          "unifi.in.reinitialized.net" = {
            forceSSL = true;
            enableACME = true;
            listenAddresses = [
              "10.1.12.4"
            ];

            locations."/" = {
              proxyPass = "https://10.255.0.4:8443";
              extraConfig = internalOnly;
            };
          };
        };
      };
    };
  };
}