# hosts/apps1.nix
## Contains all essential reinitialized.net applications and services
{ ... }:
let
  huduEnv = import ../secrets/hudu.nix;
in
{
  imports = [
    ../hardware/qemu.nix

    ../modules/docker.nix
    ../modules/standard.nix
  ];
  # Network Configuration
  networking = {
    hostName = "apps1";
    # Disable DHCP for static configuration
    useDHCP = false;
    # Set Firewall rules
    firewall = {
      allowedTCPPorts = [ 80 ];
      allowedUDPPorts = [ 80 ];
    };
  };
  ## We use systemd-networkd for network configuration
  systemd.network.networks = {
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
  #services.openssh.listenAddresses = [ ];

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
      cmd = [ "bundle" "exec" "sidekiq" "-C" "config/sidekiq.yml" ];
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
        ".:/app"
      ];
    };
  };

  # Setup Nginx container
  containers.nginx = {
    ephemeral = true;
    autoStart = true;
    privateNetwork = false;

    bindMounts = {
      "/var/www/hudu2/config" = {
        hostPath = "/var/www/hudu2/config";
        isReadOnly =  false;
      };
    };
    config = { ... }: {
      # Setup Nginx service
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
              { 
                addr = "[::]"; 
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
                extraConfig = ''
                  proxy_set_header Host $host;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                  proxy_read_timeout 240s;
                  proxy_send_timeout 240s;
                  proxy_set_header X-Forwarded-Proto $scheme;
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_pass_request_headers on;
                  proxy_buffering off;
                  proxy_redirect off;
                  break;
                '';
              };
              # Try files, fallback to @rails
              "/" = {
                tryFiles = "$uri @rails";
              };
              # Rails app fallback
              "@rails" = {
                extraConfig = ''
                  client_body_buffer_size 128k;

                  #Timeout if the real server is dead
                  proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;

                  # Advanced Proxy Config
                  send_timeout 5m;
                  proxy_read_timeout 240;
                  proxy_send_timeout 240;
                  proxy_connect_timeout 240;

                  # TLS 1.3 early data
                  #proxy_set_header Early-Data $ssl_early_data;

                  # Basic Proxy Config
                  proxy_set_header Host $host;
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                  #proxy_set_header X-Forwarded-Proto https;
                  proxy_set_header X-Forwarded-Host $host;
                  proxy_set_header X-Forwarded-Ssl off;
                  proxy_redirect  http://  $scheme://;
                  proxy_http_version 1.1;
                  proxy_set_header Connection "";
                  #proxy_cookie_path / "/; HTTPOnly; Secure"; # enable at your own risk, may break certain apps
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