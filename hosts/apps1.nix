{
  self,
  defaultStateVersion,
  pkgs,
  config,
  ...
}:{
  # Networking Configuration
  networking = {
    hostName = "apps1";
    useDHCP = false;
    firewall.whitelist = [
      # Allow DNS traffic
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
        "10.1.11.2/24"
      ];
      dns = [
        "10.1.12.3"
        #"127.0.0.1"
        #"10.1.11.3"
      ];
      gateway = [
        "10.1.11.1"
      ];
      matchConfig.Path = "pci-0000:06:12.0";
    };
  };
  # Configure MeshNetwork
  services.meshNetwork = {
      enable = true;
      nodeId = 3;
  };
  # Hosted Services
  ## Docker-based Containers
  virtualisation.oci-containers.containers = {
    ### Hudu
    hudu_postgres1 = {
      autoStart = true;
      hostname = "hudu_postgres1";
      image = "docker.io/library/postgres:18-alpine";
      environment = config.secrets.hudu.keys;
      networks = [ 
        "backend"
      ];
      volumes = [
        "hudu_postgres1Data:/var/lib/postgresql/data"
      ];
    };
    hudu_redis1 = {
      autoStart = true;
      hostname = "hudu_redis1";
      image = "docker.io/library/redis:8-alpine";
      environment = config.secrets.hudu.keys;
      cmd = [ "redis-server" ];
      networks = [ 
        "backend"
      ];
      volumes = [
        "hudu_redis1Data:/var/lib/redis/data"
      ];
    };
    hudu1 = {
      autoStart = true;      
      hostname = "hudu1";
      image = "hududocker/hudu:latest";
      environment = config.secrets.hudu.keys;
      dependsOn = [
        "hudu_postgres1"
        "hudu_redis1"
      ];
      networks = [ 
        "backend"
      ];
      ports = [
        "10.255.0.3:3000:3000"
      ];
      volumes = [
        "hudu_data:/var/www/hudu2/public/uploads/"
        "hudu_data:/var/www/hudu2/uploads"
        "hudu_data:/var/lib/app/data"
      ];
    };
    hudu2 = {
      autoStart = true;
      hostname = "hudu2";
      image = "hududocker/hudu:latest";
      environment = config.secrets.hudu.keys;
      cmd = [ 
        "bundle" 
        "exec" 
        "sidekiq" 
        "-C" 
        "config/sidekiq.yml"
      ];
      dependsOn = [
        "hudu_postgres1"
        "hudu_redis1"
      ];
      networks = [ 
        "backend"
      ];
      volumes = [
        "hudu_data:/var/www/hudu2/public/uploads/"
        "hudu_data:/var/www/hudu2/uploads"
      ];
    };
    ### Technitium oneDns
    dnsOne = {
      autoStart = true;
      hostname = "dnsOne";
      image = "docker.io/technitium/dns:14.3.0";
      volumes = [
        "technitium_data:/etc/dns"
      ];
      networks = [
        "backend"
      ];
    };
  };
    ### Create required folders
  systemd.tmpfiles.rules = [
    "d /mnt/data/nix/nginx1 0755 root root - -"
  ];
  ### Container Configuration
  containers.nginx1 = {
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
}