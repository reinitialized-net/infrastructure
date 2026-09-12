{
  config,
  lib,
  ...
}:
{
  secrets = {
    # Provision private-key files separately before services start on every boot.
    # Keep these persistent paths root-owned and inaccessible to other users.
    meshNetwork = {
      description = "MeshNetwork secrets";
      file = lib.mkDefault "/var/lib/wireguard/wg-mesh.key";
    };
    infraAutomation = {
      description = "Forgejo bot credentials and metadata for automated infrastructure update failure reporting";
      file = lib.mkDefault "/var/lib/infratainer/secrets/infra-automation-token";
      keys = {
        forgejoBaseUrl = "https://git.ds.reinitialized.net";
        repoOwner = "reinitialized.net";
        repoName = "infrastructure";
        issueLabels = "infra-auto-update";
      };
    };
    acmeDns = {
      description = "Technitium DNS credentials for ACME";
      # Provision this root-owned file (0600) separately. It must contain:
      # TECHNITIUM_API_TOKEN=<token>
      # TECHNITIUM_SERVER_BASE_URL=http://10.255.0.3:1026/
      file = lib.mkDefault "/var/lib/service-secrets/acme-dns.env";
    };

    hudu = {
      description = "Hudu secrets";
      # Prefer a separately provisioned persistent environment file in production.
      # file = "/var/lib/service-secrets/hudu.env";
      # Set keys = {} when the environment file contains all Hudu settings.
      keys = {
        SECRET_KEY_BASE = "PLACE_GENERATED_SECRET_KEY_BASE_HERE";
        PASSWORD_KEY = "PLACE_GENERATED_PASSWORD_KEY_HERE";
        DOMAIN = "docs.example.com";
        URL = "example.com";
        SUBDOMAINS = "docs";
        TWO_FACTOR_KEY = "PLACE_GENERATED_TWO_FACTOR_KEY_HERE";

        PUID = "1000";
        PGID = "1000";
        ONLY_SUBDOMAINS = "true";
        VALIDATION = "http";
        STAGING = "false";
        DISABLE_SSL = "true";

        # Database connection to PostgreSQL on db1.
        DB_HOST = "10.255.0.11";
        DB_PORT = "1024";
        DB_USERNAME = "hudu";
        DB_PASSWORD = "PLACE_DB_PASSWORD_HERE";
        DB_NAME = "hudu_production";

        SMTP_DOMAIN = "smtp.example.com";
        SMTP_ADDRESS = "smtp.example.com";
        SMTP_PORT = "587";
        SMTP_STARTTLS_AUTO = "true";
        SMTP_USERNAME = "";
        SMTP_PASSWORD = "";
        SMTP_AUTHENTICATION = "login";
        SMTP_OPENSSL_VERIFY_MODE = "peer";
        SMTP_FROM_ADDRESS = "";

        USE_LOCAL_FILESYSTEM = "true";
        AUTHENTICATE_UPLOADS = "true";

        RAILS_ENV = "production";
        RACK_ENV = "production";
        RAILS_MAX_THREADS = "50";

        REDIS_URL = "redis://10.255.0.11:1025";
      };
    };

    volumeMigration = {
      description = "SSH private key for docker volume migration between hosts";
      file = lib.mkDefault "/var/lib/service-secrets/docker-volume-migration.key";
    };

    jaeger = {
      # Optional root-owned runtime env file; omit duplicate keys below when used.
      # file = "/var/lib/service-secrets/jaeger.env";
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
      # Optional root-owned runtime env file; omit duplicate keys below when used.
      # file = "/var/lib/service-secrets/grafana.env";
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

    forgejo = {
      # Optional root-owned runtime env file; omit duplicate keys below when used.
      # file = "/var/lib/service-secrets/forgejo.env";
      description = "Forgejo git forge configuration";
      keys = {
        # Auto-registration for OAuth2/OIDC logins via Authentik
        # ENABLE_AUTO_REGISTRATION: Creates a new user account on first OIDC login
        # ACCOUNT_LINKING: Links OIDC identity to existing local account by email match
        FORGEJO__oauth2_client__ENABLE_AUTO_REGISTRATION = "true";
        FORGEJO__oauth2_client__ACCOUNT_LINKING = "auto";
      };
    };

    authentik = {
      # Optional root-owned runtime env file; omit duplicate keys below when used.
      # file = "/var/lib/service-secrets/authentik.env";
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
        AUTHENTIK_EMAIL__HOST = "stalwart";
        AUTHENTIK_EMAIL__PORT = "587";
        AUTHENTIK_EMAIL__USE_TLS = "true";
        AUTHENTIK_EMAIL__USERNAME = "PLACE_STALWART_USER@reinitialized.net";
        AUTHENTIK_EMAIL__PASSWORD = "PLACE_STALWART_PASSWORD_HERE";
        AUTHENTIK_EMAIL__FROM = "authentik@reinitialized.net";
      };
    };
  };
}
