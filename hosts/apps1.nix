# hosts/apps1.nix
## Contains all essential reinitialized.net applications and services
{ ... }:
let
  secrets = (import ../secrets/hudu.nix);
  huduEnv = {
    SECRET_KEY_BASE = secrets.SECRET_KEY_BASE;
    PASSWORD_KEY = secrets.PASSWORD_KEY;
    DOMAIN = secrets.DOMAIN;
    URL = secrets.URL;
    SUBDOMAINS = secrets.SUBDOMAINS;
    TWO_FACTOR_KEY = secrets.TWO_FACTOR_KEY;

    PUID = secrets.PUID;
    PGID = secrets.PGID;
    ONLY_SUBDOMAINS = secrets.ONLY_SUBDOMAINS;
    VALIDATION = secrets.VALIDATION;
    STAGING = secrets.STAGING;

    DB_HOST = secrets.DB_HOST;
    DB_USERNAME = secrets.DB_USERNAME;
    DB_PASSWORD = secrets.DB_PASSWORD;
    DB_NAME = secrets.DB_NAME;
    POSTGRES_HOST_AUTH_METHOD = secrets.POSTGRES_HOST_AUTH_METHOD;

    SMTP_DOMAIN = secrets.SMTP_DOMAIN;
    SMTP_ADDRESS = secrets.SMTP_ADDRESS;
    SMTP_PORT = secrets.SMTP_PORT;
    SMTP_STARTTLS_AUTO = secrets.SMTP_STARTTLS_AUTO;
    SMTP_USERNAME = secrets.SMTP_USERNAME;
    SMTP_PASSWORD = secrets.SMTP_PASSWORD;
    SMTP_AUTHENTICATION = secrets.SMTP_AUTHENTICATION;
    SMTP_OPENSSL_VERIFY_MODE = secrets.SMTP_OPENSSL_VERIFY_MODE;
    SMTP_FROM_ADDRESS = secrets.SMTP_FROM_ADDRESS;

    USE_LOCAL_FILESYSTEM = secrets.USE_LOCAL_FILESYSTEM;
    AUTHENTICATE_UPLOADS = secrets.AUTHENTICATE_UPLOADS;

    RAILS_ENV = secrets.RAILS_ENV;
    RACK_ENV = secrets.RACK_ENV;
    RAILS_MAX_THREADS = secrets.RAILS_MAX_THREADS;

    REDIS_URL = secrets.REDIS_URL;
  };
in
{
  imports = [
    ../hardware/qemu.nix

    ../modules/docker.nix
    ../modules/standard.nix
  ];

  # System-specific configuration
  networking = {
    hostName = "apps1";

    firewall = {
      allowedTCPPorts = [ 80 ];
      allowedUDPPorts = [ 80 ];
    };
  };
  #services.openssh.listenAddresses = [ ];

  virtualisation.oci-containers.containers = {
    postgres1 = {
      autoStart = true;
      environment = huduEnv;
      log-driver = "json-file";
      image = "docker.io/library/postgres:18-alpine";
      volumes = [
        "postgres1_data:/var/lib/postgresql/data"
      ];
    };
    redis1 = {
      autoStart = true;
      environment = huduEnv;
      cmd = [ "redis-server" ];
      image = "docker.io/library/redis:8-alpine";
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
      image = "docker.io/hudu/hudu:latest";
      ports = [ "127.0.0.1:3000:3000" ];
      volumes = [
        "hudu_data:/var/www/hudu2/public/uploads/"
        "hudu_data:/var/www/hudu2/uploads"
        "hudu_data:/var/lib/app/data"
      ];
    };
    hudu2 = {
      autoStart = true;
      cmd = [ "bundle exec sidekiq -C config/sidekiq.yml" ];
      dependsOn = [
        "postgres1"
        "redis1"
      ];
      environment = huduEnv;
      image = "docker.io/hudu/hudu:latest";
      volumes = [
        "hudu_data:/var/www/hudu2/public/uploads/"
        "hudu_data:/var/www/hudu2/uploads"
        "hudu_data:/app"
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
            forceSSL = true;
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
            index = "index.html";
            locations = {
              # Deny access to dotfiles
              "/." = {
                extraConfig = ''
                  deny all;
                '';
              };
              # Deny access to .rb and .log files
              "/~* ^.+\.(rb|log)$" = {
                extraConfig = ''
                  deny all;
                '';
              };
              # WebSocket cable proxy
              "/cable" = {
                proxyPass = "http://127.0.0.1:3000/cable";
                proxyWebsockets = true;
                extraConfig = ''
                  proxy_http_version 1.1;
                  proxy_set_header Upgrade $http_upgrade;
                  proxy_set_header Connection "upgrade";
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
                  proxy_pass http://hudu1:3000;
                '';
              };
            };
          };
        };
      };
    };
  };
}