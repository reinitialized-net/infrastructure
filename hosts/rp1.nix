{
  defaultStateVersion,
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
      # Mail server ports (stalwartOne via 10.1.12.4)
      {
        port = 25;
        protocol = "tcp";
        ipType = "ipv4";
        source = [
          "0.0.0.0/0"
        ];
      }
      {
        port = 465;
        protocol = "tcp";
        ipType = "ipv4";
        source = [
          "0.0.0.0/0"
        ];
      }
      {
        port = 587;
        protocol = "tcp";
        ipType = "ipv4";
        source = [
          "0.0.0.0/0"
        ];
      }
      {
        port = 143;
        protocol = "tcp";
        ipType = "ipv4";
        source = [
          "0.0.0.0/0"
        ];
      }
      {
        port = 993;
        protocol = "tcp";
        ipType = "ipv4";
        source = [
          "0.0.0.0/0"
        ];
      }
      {
        port = 995;
        protocol = "tcp";
        ipType = "ipv4";
        source = [
          "0.0.0.0/0"
        ];
      }
      {
        port = 4190;
        protocol = "tcp";
        ipType = "ipv4";
        source = [
          "10.0.0.0/8"
          "172.16.0.0/12"
          "192.168.0.0/16"
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
    dockerIntegration = false;
  };
  # Ensure container directories exist
  systemd.tmpfiles.rules = [
    "d /mnt/containers/nginx/var/lib/acme 0750 root root -"
  ];
  # Ensure nginx container waits for WireGuard mesh to be online before starting
  # This is needed because ACME uses Technitium DNS API via mesh network
  systemd.services."container@nginx" = {
    after = [ "sys-devices-virtual-net-wg\\x2dmesh.device" ];
    wants = [ "sys-devices-virtual-net-wg\\x2dmesh.device" ];
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
    };

    config = { lib, pkgs, ... }: {
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

        # Stream configuration for DNS and SSL passthrough
        streamConfig = ''
          ## Upstreams
          # Technitium DNS (via mesh network)
          upstream dnsOneService {
            server 10.1.11.2:53;
          }
          upstream dnsTwoService {
            server 10.1.11.3:53;
          }
          upstream dnsOneUI {
            server 10.255.0.3:53443;
          }
          upstream dnsTwoUI {
            server 10.255.0.4:53443;
          }
          # UniFi Controller
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
          # Stalwart Mail HTTP backends (for stream SSL termination + PROXY protocol)
          upstream stalwartOneHttp {
            server 10.255.0.3:8080;
          }
          upstream stalwartOneSmtp {
            server 10.255.0.3:25;
          }
          upstream stalwartOneSmtps {
            server 10.255.0.3:465;
          }
          upstream stalwartOneSubmission {
            server 10.255.0.3:587;
          }
          upstream stalwartOneImap {
            server 10.255.0.3:143;
          }
          upstream stalwartOneImaps {
            server 10.255.0.3:993;
          }
          upstream stalwartOnePop3s {
            server 10.255.0.3:995;
          }
          upstream stalwartOneSieve {
            server 10.255.0.3:4190;
          }
          # Stalwart Mail (stalwartTwo on apps2 - future)
          upstream stalwartTwoHttp {
            server 10.255.0.4:8080;
          }
          upstream stalwartTwoSmtp {
            server 10.255.0.4:25;
          }
          upstream stalwartTwoSmtps {
            server 10.255.0.4:465;
          }
          upstream stalwartTwoSubmission {
            server 10.255.0.4:587;
          }
          upstream stalwartTwoImap {
            server 10.255.0.4:143;
          }
          upstream stalwartTwoImaps {
            server 10.255.0.4:993;
          }
          upstream stalwartTwoPop3s {
            server 10.255.0.4:995;
          }
          upstream stalwartTwoSieve {
            server 10.255.0.4:4190;
          }
          # Local mail SSL termination upstreams (stream terminates SSL, then forwards HTTP)
          upstream mailLocalTermination {
            server 127.0.0.1:8443;
          }
          upstream mail2LocalTermination {
            server 127.0.0.1:8444;
          }

          ## SNI routing maps for HTTPS on shared IPs
          # 10.1.12.2: one.dns (passthrough) vs mail (local SSL termination)
          map $ssl_preread_server_name $https_backend_12_2 {
            one.dns.reinitialized.net dnsOneUI;
            mail.reinitialized.net    mailLocalTermination;
            default                   dnsOneUI;
          }
          # 10.1.12.3: two.dns (passthrough) vs mail2 (local SSL termination)
          map $ssl_preread_server_name $https_backend_12_3 {
            two.dns.reinitialized.net dnsTwoUI;
            mail2.reinitialized.net   mail2LocalTermination;
            default                   dnsTwoUI;
          }

          ## Mail HTTPS - Stream SSL termination + PROXY protocol
          # rp1 terminates SSL using ACME certs, then forwards plain HTTP
          # with PROXY protocol header so Stalwart knows the real client IP
          server {
            listen 127.0.0.1:8443 ssl;
            ssl_certificate /var/lib/acme/mail.reinitialized.net/fullchain.pem;
            ssl_certificate_key /var/lib/acme/mail.reinitialized.net/key.pem;
            proxy_pass stalwartOneHttp;
            proxy_protocol on;
          }
          server {
            listen 127.0.0.1:8444 ssl;
            ssl_certificate /var/lib/acme/mail2.reinitialized.net/fullchain.pem;
            ssl_certificate_key /var/lib/acme/mail2.reinitialized.net/key.pem;
            proxy_pass stalwartTwoHttp;
            proxy_protocol on;
          }

          ## DNS Service Listeners (Layer 4)
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

          ## HTTPS with SNI routing (Layer 4)
          # Routes based on hostname:
          # - DNS UI: passthrough to backend (backend handles cert)
          # - Mail: route to local nginx for SSL termination (rp1 handles cert)
          server {
            listen 10.1.12.2:443;
            ssl_preread on;
            proxy_pass $https_backend_12_2;
            proxy_connect_timeout 10s;
          }
          server {
            listen 10.1.12.3:443;
            ssl_preread on;
            proxy_pass $https_backend_12_3;
            proxy_connect_timeout 10s;
          }

          ## UniFi Controller Listeners
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

          ## Stalwart Mail Listeners on 10.1.12.2 (stalwartOne)
          ## All include proxy_protocol so Stalwart receives real client IPs
          server {
            listen 10.1.12.2:25;
            proxy_pass stalwartOneSmtp;
            proxy_protocol on;
          }
          server {
            listen 10.1.12.2:465;
            proxy_pass stalwartOneSmtps;
            proxy_protocol on;
          }
          server {
            listen 10.1.12.2:587;
            proxy_pass stalwartOneSubmission;
            proxy_protocol on;
          }
          server {
            listen 10.1.12.2:143;
            proxy_pass stalwartOneImap;
            proxy_protocol on;
          }
          server {
            listen 10.1.12.2:993;
            proxy_pass stalwartOneImaps;
            proxy_protocol on;
          }
          server {
            listen 10.1.12.2:995;
            proxy_pass stalwartOnePop3s;
            proxy_protocol on;
          }
          server {
            listen 10.1.12.2:4190;
            proxy_pass stalwartOneSieve;
            proxy_protocol on;
          }

          ## Stalwart Mail Listeners on 10.1.12.3 (stalwartTwo - future)
          ## All include proxy_protocol so Stalwart receives real client IPs
          server {
            listen 10.1.12.3:25;
            proxy_pass stalwartTwoSmtp;
            proxy_protocol on;
          }
          server {
            listen 10.1.12.3:465;
            proxy_pass stalwartTwoSmtps;
            proxy_protocol on;
          }
          server {
            listen 10.1.12.3:587;
            proxy_pass stalwartTwoSubmission;
            proxy_protocol on;
          }
          server {
            listen 10.1.12.3:143;
            proxy_pass stalwartTwoImap;
            proxy_protocol on;
          }
          server {
            listen 10.1.12.3:993;
            proxy_pass stalwartTwoImaps;
            proxy_protocol on;
          }
          server {
            listen 10.1.12.3:995;
            proxy_pass stalwartTwoPop3s;
            proxy_protocol on;
          }
          server {
            listen 10.1.12.3:4190;
            proxy_pass stalwartTwoSieve;
            proxy_protocol on;
          }
        '';
        virtualHosts = {
          "one.dns.reinitialized.net" = {
            # Only listen on HTTP to redirect to HTTPS
            # HTTPS traffic is handled by stream passthrough (no cert on rp1)
            onlySSL = false;
            enableACME = false;
            addSSL = false;
            listen = [
              { addr = "10.1.12.2"; port = 80; ssl = false; }
            ];

            # Redirect all HTTP traffic to HTTPS
            locations."/" = {
              return = "301 https://$host$request_uri";
            };
          };
          "two.dns.reinitialized.net" = {
            # Only listen on HTTP to redirect to HTTPS
            # HTTPS traffic is handled by stream passthrough (no cert on rp1)
            onlySSL = false;
            enableACME = false;
            addSSL = false;
            listen = [
              { addr = "10.1.12.3"; port = 80; ssl = false; }
            ];

            # Redirect all HTTP traffic to HTTPS
            locations."/" = {
              return = "301 https://$host$request_uri";
            };
          };

          "mail.reinitialized.net" = {
            # HTTP-only: serves ACME HTTP-01 challenges and redirects to HTTPS
            # HTTPS is handled by stream SSL termination with PROXY protocol
            onlySSL = false;
            enableACME = true;
            addSSL = false;
            listen = [
              { addr = "10.1.12.2"; port = 80; ssl = false; }
            ];

            locations."/" = {
              return = "301 https://$host$request_uri";
            };
          };

          "mail2.reinitialized.net" = {
            # HTTP-only: serves ACME HTTP-01 challenges and redirects to HTTPS
            # HTTPS is handled by stream SSL termination with PROXY protocol
            onlySSL = false;
            enableACME = true;
            addSSL = false;
            listen = [
              { addr = "10.1.12.3"; port = 80; ssl = false; }
            ];

            locations."/" = {
              return = "301 https://$host$request_uri";
            };
          };

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

          "unifi.in.reinitialized.net" = {
            forceSSL = true;
            enableACME = true;
            listenAddresses = [
              "10.1.12.4"
            ];

            locations."/" = {
              proxyPass = "https://10.255.0.4:8443";
              extraConfig = ''
                ${internalOnly}
                proxy_ssl_verify off;
              '';
            };
          };
        };
      };
    };
  };
}