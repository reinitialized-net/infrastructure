{
  config,
  pkgs,
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
      # port 8443 removed: mail SSL termination moved to Stalwart native ACME
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

  # Ensure nginx user can access ACME files
  users.users.nginx = {
    extraGroups = [ "acme" ];
  };

  # Enable ACME for automatic SSL certificates
  # Uses DNS-01 challenge via Technitium DNS API (over mesh network)
  # This works for all domains including internal-only *.in.reinitialized.net
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "admin@reinitialized.net";
      #server = "https://acme-staging-v02.api.letsencrypt.org/directory";
      profile = "shortlived";
      dnsProvider = "technitium";
      credentialsFile = config.secrets.acmeDns.file;
      dnsResolver = "10.255.0.3:1028";
      extraLegoFlags = [ 
        "--pfx"
        "--pfx.pass="
        "--dns.resolvers=10.255.0.4:1026"
        "--dns.propagation-wait=30s"
        "--dns-timeout=300"
      ];
    };
    # mail.reinitialized.net cert removed: Stalwart handles its own TLS via native ACME (HTTP-01)
  };

  # Nginx Reverse Proxy
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
        server 10.255.0.3:1027;
      }
      upstream dnsTwoUI {
        server 10.255.0.4:1025;
      }
      # UniFi Controller
      upstream unifiWeb {
        server 10.255.0.4:1027;
      }
      upstream unifiComm {
        server 10.255.0.4:1030;
      }
      upstream unifiStun {
        server 10.255.0.4:1028;
      }
      upstream unifiDiscovery {
        server 10.255.0.4:1029;
      }
      # Stalwart Mail backends (TCP passthrough with PROXY protocol)
      # Stalwart handles TLS natively via its built-in ACME (HTTP-01)
      upstream stalwartOneHttp {
        server 10.255.0.3:1029;
      }
      upstream stalwartOneHttps {
        server 10.255.0.3:1042;
      }
      upstream stalwartOneSmtp {
        server 10.255.0.3:1030;
      }
      upstream stalwartOneImap {
        server 10.255.0.3:1031;
      }
      upstream stalwartOneSmtps {
        server 10.255.0.3:1032;
      }
      upstream stalwartOneSubmission {
        server 10.255.0.3:1033;
      }
      upstream stalwartOneImaps {
        server 10.255.0.3:1034;
      }
      upstream stalwartOnePop3s {
        server 10.255.0.3:1035;
      }
      upstream stalwartOneSieve {
        server 10.255.0.3:1036;
      }

      # Local intermediate for mail HTTPS: adds PROXY protocol before
      # forwarding to Stalwart's HTTPS listener. Needed because the SNI routing
      # server block also handles DNS UI traffic which must NOT receive PROXY protocol.
      upstream mailProxyProtocol {
        server 127.0.0.1:8443;
      }

      ## SNI routing maps for HTTPS on shared IPs
      # 10.1.12.2: one.dns (passthrough) vs mail (via local PROXY protocol relay)
      map $ssl_preread_server_name $https_backend_12_2 {
        one.dns.reinitialized.net dnsOneUI;
        mail.reinitialized.net    mailProxyProtocol;
        default                   dnsOneUI;
      }
      # 10.1.12.3: two.dns (passthrough only, no other services currently)
      map $ssl_preread_server_name $https_backend_12_3 {
        two.dns.reinitialized.net dnsTwoUI;
        default                   dnsTwoUI;
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
      # - Mail: routed to local relay that adds PROXY protocol, then to Stalwart
      server {
        listen 10.1.12.2:443;
        ssl_preread on;
        proxy_pass $https_backend_12_2;
        proxy_connect_timeout 10s;
      }

      ## Mail HTTPS - PROXY protocol relay
      # Receives mail HTTPS from SNI routing above, adds PROXY protocol header,
      # then forwards TCP stream to Stalwart's HTTPS listener (port 443 in container).
      # PROXY protocol is REQUIRED because Stalwart's trusted-networks includes
      # rp1's mesh IP (10.255.0.2/32) and expects PROXY headers to preserve client IPs.
      server {
        listen 127.0.0.1:8443;
        proxy_pass stalwartOneHttps;
        proxy_protocol on;
      }

      ## Mail HTTP - PROXY protocol relay for ACME challenges
      # nginx virtualHost (port 80) proxies /.well-known/acme-challenge/ to this relay.
      # The relay adds PROXY protocol before forwarding to Stalwart's HTTP listener,
      # because direct HTTP proxy_pass from rp1 (10.255.0.2) would be rejected by
      # Stalwart's trusted-networks without PROXY protocol headers.
      server {
        listen 127.0.0.1:8480;
        proxy_pass stalwartOneHttp;
        proxy_protocol on;
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
        # HTTP listener for:
        # 1. Proxying ACME HTTP-01 challenges to Stalwart (native cert management)
        # 2. Redirecting all other HTTP traffic to HTTPS
        # HTTPS is handled by stream TCP passthrough to Stalwart (see streamConfig)
        onlySSL = false;
        enableACME = false;
        addSSL = false;
        listen = [
          { addr = "10.1.12.2"; port = 80; ssl = false; }
        ];

        locations = {
          # Proxy ACME HTTP-01 challenge to Stalwart via local stream relay
          # Let's Encrypt validates at http://mail.reinitialized.net/.well-known/acme-challenge/<TOKEN>
          # Must go through stream relay (127.0.0.1:8480) to add PROXY protocol headers,
          # because Stalwart's trusted-networks (10.255.0.2/32) rejects plain HTTP from rp1's mesh IP
          "/.well-known/acme-challenge/" = {
            proxyPass = "http://127.0.0.1:8480";
          };
          # Redirect everything else to HTTPS
          "/" = {
            return = "301 https://$host$request_uri";
          };
        };
      };

      "docs.reinitialized.net" = {
        forceSSL = true;
        enableACME = true;
        acmeRoot = null;
        serverAliases = [ "www.docs.reinitialized.net" ];
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
            proxyPass = "http://10.255.0.3:1025/cable";
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
              proxy_pass http://10.255.0.3:1025;
            '';
          };
        };
      };
      "media.reinitialized.me" = {
        forceSSL = true;
        enableACME = true;
        acmeRoot = null;
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
        acmeRoot = null;
        listenAddresses = [
          "10.1.12.4"
        ];

        locations."/" = {
          proxyPass = "https://10.255.0.4:1027";
          extraConfig = ''
            ${internalOnly}
            proxy_ssl_verify off;
          '';
        };
      };
      "pgadmin.in.reinitialized.net" = {
        forceSSL = true;
        enableACME = true;
        acmeRoot = null;
        listenAddresses = [
          "10.1.12.4"
        ];

        locations."/" = { 
          proxyPass = "http://10.255.0.4:1031";
        };
      };
      "redisadmin.in.reinitialized.net" = {
        forceSSL = true;
        enableACME = true;
        acmeRoot = null;
        listenAddresses = [
          "10.1.12.4"
        ];

        locations."/" = {
          proxyPass = "http://10.255.0.4:1032";
          proxyWebsockets = true;
        };
      };
      "git.ds.reinitialized.net" = {
        forceSSL = true;
        enableACME = true;
        acmeRoot = null;
        listenAddresses = [
          "10.1.12.4"
        ];

        locations."/" = {
          proxyPass = "http://10.255.0.3:1037";
          extraConfig = ''
            client_max_body_size 512M;
          '';
        };
      };

      # Telemetry and Observability Services
      "jaeger.in.reinitialized.net" = {
        forceSSL = true;
        enableACME = true;
        acmeRoot = null;
        listenAddresses = [
          "10.1.12.4"
        ];

        locations."/" = {
          proxyPass = "http://10.255.0.3:1039";
          extraConfig = ''
            ${internalOnly}
          '';
        };
      };

      "grafana.in.reinitialized.net" = {
        forceSSL = true;
        enableACME = true;
        acmeRoot = null;
        listenAddresses = [
          "10.1.12.4"
        ];

        locations."/" = {
          proxyPass = "http://10.255.0.3:1040";
          extraConfig = ''
            ${internalOnly}
          '';
        };
      };

      "prometheus.in.reinitialized.net" = {
        forceSSL = true;
        enableACME = true;
        acmeRoot = null;
        listenAddresses = [
          "10.1.12.4"
        ];

        locations."/" = {
          proxyPass = "http://10.255.0.11:1029";
          extraConfig = ''
            ${internalOnly}
          '';
        };
      };

      "photos.reinitialized.me" = {
        forceSSL = true;
        enableACME = true;
        acmeRoot = null;
        listenAddresses = [
          "10.1.12.4"
        ];

        locations."/" = {
          proxyPass = "http://10.255.0.5:1001";
          proxyWebsockets = true;
          extraConfig = ''
            # allow large file uploads (0 = no limit)
            client_max_body_size 0;
            # disable buffering to prevent OOM and make uploads ~2x faster
            proxy_request_buffering off;
            # increase body buffer to avoid limiting upload speed (default 8k/16k)
            client_body_buffer_size 1024k;
            # set timeouts for large uploads
            proxy_read_timeout 600s;
            proxy_send_timeout 600s;
            send_timeout 600s;
          '';
        };
      };
      # Cinny Matrix Web Client (on apps2)
      "chat.reinitialized.me" = {
        forceSSL = true;
        enableACME = true;
        acmeRoot = null;
        listenAddresses = [
          "10.1.12.4"
        ];

        locations."/" = {
          proxyPass = "http://10.255.0.4:1040";
        };
      };

      # Matrix Homeserver (Conduwuit on apps3) + well-known discovery
      "reinitialized.me" = {
        forceSSL = true;
        enableACME = true;
        acmeRoot = null;
        listenAddresses = [
          "10.1.12.4"
        ];

        locations = {
          # Well-known client discovery (required by Matrix spec)
          "/.well-known/matrix/client" = {
            extraConfig = ''
              default_type application/json;
              add_header Access-Control-Allow-Origin *;
              return 200 '{"m.homeserver": {"base_url": "https://reinitialized.me"}}';
            '';
          };
          # Well-known server discovery
          "/.well-known/matrix/server" = {
            extraConfig = ''
              default_type application/json;
              return 200 '{"m.server": "reinitialized.me:443"}';
            '';
          };
          # Matrix client and server API
          "/_matrix" = {
            proxyPass = "http://10.255.0.5:1025";
            proxyWebsockets = true;
            extraConfig = ''
              client_max_body_size 100M;
              proxy_read_timeout 600s;
              proxy_send_timeout 600s;
            '';
          };
        };
      };

      "admin.staging.bleupigs.club" = {
        forceSSL = true;
        enableACME = true;
        acmeRoot = null;
        listenAddresses = [
          "10.1.12.4"
        ];

        locations."/" = {
          proxyPass = "http://10.255.0.1:4006";
        };
        locations."/ws/" = {
          proxyPass = "http://10.255.0.1:4003";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_read_timeout 86400;
            proxy_send_timeout 86400;
          '';
        };
      };
      "membership.staging.bleupigs.club" = {
        forceSSL = true;
        enableACME = true;
        acmeRoot = null;
        listenAddresses = [
          "10.1.12.4"
        ];

        locations."/" = {
          proxyPass = "http://10.255.0.1:4003";
        };
        locations."/ws/" = {
          proxyPass = "http://10.255.0.1:4003";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_read_timeout 86400;
            proxy_send_timeout 86400;
          '';
        };
      };
    };
  };
}