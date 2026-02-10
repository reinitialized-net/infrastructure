{
  config,
  lib,
  ...
}: {
  secrets = {
    meshNetwork = {
      description = "MeshNetwork secrets";
      file = lib.mkDefault (builtins.toFile "mesh-privatekey" "PLACE PRIVATE KEY HERE");
    };
    acmeDns = {
      description = "Technitium DNS API token for ACME DNS-01 challenges";
      file = lib.mkDefault (builtins.toFile "acme-dns-token" ''
        TECHNITIUM_API_TOKEN=${config.secrets.acmeDns.keys.apiToken}
        TECHNITIUM_SERVER_BASE_URL=http://10.255.0.3:5380/
      '');
      keys = {
        apiToken = "PLACE API TOKEN HERE";
      };
    };
    
    hudu = {
      description = "Hudu secrets";
      keys = {
        SECRET_KEY_BASE = "783471e6e7f1e100e19f4c9898e679ea308d017efbf3f5eff69ffca663dfdff043d90d066dddcf584cee537bd6cbcc6957e1373567f8ebf1450b35c361074575";
        PASSWORD_KEY = "640f83885bbbb4b376b2fcd6f5ddc1cc";
        DOMAIN = "docs.example.com";
        URL = "example.com";
        SUBDOMAINS = "docs";
        TWO_FACTOR_KEY = "761ee57449c16ae2e32ef22a6442101b";

        PUID = "1000";
        PGID = "1000";
        ONLY_SUBDOMAINS = "true";
        VALIDATION = "http";
        STAGING = "false";
        DISABLE_SSL = "true";

        # Database connection - use container hostname for local DB
        # For remote database, use IP address and separate port:
        #   DB_HOST = "10.255.0.11";
        #   DB_PORT = "1024";
        DB_HOST = "postgres1";
        DB_USERNAME = "postgres";
        DB_PASSWORD = "";
        DB_NAME = "hudu_production";
        POSTGRES_HOST_AUTH_METHOD = "trust";

        SMTP_DOMAIN = "smtp.example.com";
        SMTP_ADDRESS = "smtp.example.com";
        SMTP_PORT = "587";
        SMTP_STARTTLS_AUTO = "true";
        SMTP_USERNAME = "";
        SMTP_PASSWORD = "";
        SMTP_AUTHENTICATION = "login";
        SMTP_OPENSSL_VERIFY_MODE = "none";
        SMTP_FROM_ADDRESS = "";

        USE_LOCAL_FILESYSTEM = "true";
        AUTHENTICATE_UPLOADS = "true";

        RAILS_ENV = "production";
        RACK_ENV = "production";
        RAILS_MAX_THREADS = "50";

        REDIS_URL = "redis://redis1";
      };
    volumeMigration = {
      description = "SSH private key for docker volume migration between hosts";
      file = lib.mkDefault (builtins.toFile "volume-migration-key" "PLACE PRIVATE KEY HERE");
    };

    };

    jaeger = {
      description = "Jaeger telemetry backend configuration";
      keys = {
        SPAN_STORAGE_TYPE = "badger";
        BADGER_EPHEMERAL = "false";
        BADGER_DIRECTORY_VALUE = "/badger/data";
        BADGER_DIRECTORY_KEY = "/badger/key";
        COLLECTOR_OTLP_ENABLED = "true";
      };
    };

    grafana = {
      description = "Grafana visualization configuration";
      keys = {
        GF_SECURITY_ADMIN_USER = "admin";
        GF_SECURITY_ADMIN_PASSWORD = "CHANGE_ME_SECURE_PASSWORD";
        GF_INSTALL_PLUGINS = "";
        GF_SERVER_ROOT_URL = "http://grafana.example.com";
      };
    };

    stalwart = {
      description = "Stalwart telemetry and monitoring configuration";
      keys = {
        # These environment variables are for future use
        # Telemetry is configured via Stalwart's config.toml file
        # which is persisted in the stalwart_data volume
      };
    };
  };
}
