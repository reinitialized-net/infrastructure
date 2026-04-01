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
      description = "Stalwart configuration (TLS managed via Stalwart's native ACME HTTP-01)";
      keys = {
        # No environment variables needed — Stalwart's ACME is configured
        # in config.toml (persisted in stalwart_data volume).
        # Certificate domain: mail.reinitialized.net
        # ACME challenge is proxied: rp1 port 80 → Stalwart HTTP listener
      };
    };

    authentik = {
      description = "Authentik identity provider configuration";
      keys = {
        AUTHENTIK_SECRET_KEY = "PLACE_GENERATED_SECRET_KEY_HERE";
        AUTHENTIK_POSTGRESQL__HOST = "10.255.0.11";
        AUTHENTIK_POSTGRESQL__PORT = "1024";
        AUTHENTIK_POSTGRESQL__USER = "authentik";
        AUTHENTIK_POSTGRESQL__PASSWORD = "PLACE_DB_PASSWORD_HERE";
        AUTHENTIK_POSTGRESQL__NAME = "authentik";
        AUTHENTIK_REDIS__HOST = "10.255.0.11";
        AUTHENTIK_REDIS__PORT = "1025";
        AUTHENTIK_REDIS__DB = "3";
      };
    };

    ocis = {
      description = "ownCloud Infinite Scale cloud storage configuration (OIDC via Authentik)";
      keys = {
        # Core settings
        OCIS_URL = "https://cloud.reinitialized.net";
        OCIS_DOMAIN = "cloud.reinitialized.net";
        OCIS_LOG_LEVEL = "info";

        # TLS handled by rp1 reverse proxy
        PROXY_TLS = "false";
        OCIS_INSECURE = "true";
        PROXY_HTTP_ADDR = "0.0.0.0:9200";

        # Disable built-in IDP (using Authentik instead)
        OCIS_EXCLUDE_RUN_SERVICES = "idp";

        # External OIDC via Authentik
        # Issuer URL format: https://<authentik-domain>/application/o/<app-slug>/
        OCIS_OIDC_ISSUER = "https://access.reinitialized.net/application/o/ocis/";
        PROXY_OIDC_ISSUER = "https://access.reinitialized.net/application/o/ocis/";
        WEB_OIDC_ISSUER = "https://access.reinitialized.net/application/o/ocis/";
        PROXY_OIDC_REWRITE_WELLKNOWN = "true";

        # OIDC client credentials (from Authentik provider config)
        WEB_OIDC_CLIENT_ID = "PLACE_OIDC_CLIENT_ID_HERE";
        OCIS_OIDC_CLIENT_ID = "PLACE_OIDC_CLIENT_ID_HERE";
        OCIS_OIDC_CLIENT_SECRET = "PLACE_OIDC_CLIENT_SECRET_HERE";

        # Auto-provision user accounts on first OIDC login
        PROXY_AUTOPROVISION_ACCOUNTS = "true";
        PROXY_AUTOPROVISION_CLAIM_USERNAME = "preferred_username";
        PROXY_AUTOPROVISION_CLAIM_EMAIL = "email";
        PROXY_AUTOPROVISION_CLAIM_DISPLAYNAME = "name";
        PROXY_USER_OIDC_CLAIM = "preferred_username";
        PROXY_USER_CS3_CLAIM = "username";

        # Role assignment via OIDC claims
        PROXY_ROLE_ASSIGNMENT_DRIVER = "oidc";

        # Admin password (used only during ocis init for initial admin user)
        IDM_ADMIN_PASSWORD = "PLACE_ADMIN_PASSWORD_HERE";
      };
    };
  };
}
