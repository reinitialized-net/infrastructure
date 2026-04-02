{
  config,
  lib,
  ...
}:
{
  secrets = {
    meshNetwork = {
      description = "MeshNetwork secrets";
      file = lib.mkDefault (builtins.toFile "mesh-privatekey" "PLACE PRIVATE KEY HERE");
    };
    volumeMigration = {
      description = "SSH private key for docker volume migration between hosts";
      file = lib.mkDefault (builtins.toFile "volume-migration-key" "PLACE PRIVATE KEY HERE");
    };
    immich = {
      description = "Immich application configuration";
      keys = {
        DB_HOSTNAME = "10.255.0.11";
        DB_PORT = "1024";
        DB_USERNAME = "PLACE DB USERNAME HERE";
        DB_PASSWORD = "PLACE DB PASSWORD HERE";
        DB_DATABASE_NAME = "immich";
        REDIS_HOSTNAME = "10.255.0.11";
        REDIS_PORT = "1025";
        IMMICH_MACHINE_LEARNING_URL = "http://immich-machine-learning:3003";
      };
    };
    tuwunel = {
      description = "Tuwunel Matrix homeserver configuration";
      keys = {
        CONDUWUIT_SERVER_NAME = "reinitialized.me";
        CONDUWUIT_ADDRESS = "0.0.0.0";
        CONDUWUIT_PORT = "8008";
        CONDUWUIT_DATABASE_PATH = "/var/lib/tuwunel";
        CONDUWUIT_ALLOW_REGISTRATION = "true";
        CONDUWUIT_ALLOW_FEDERATION = "true";
        CONDUWUIT_TRUSTED_SERVERS = ''["matrix.org"]'';
        CONDUWUIT_LOG = "warn,state_res=warn";
        CONDUWUIT_MAX_REQUEST_SIZE = "104857600";
        CONDUWUIT_REGISTRATION_TOKEN = "PLACE REGISTRATION TOKEN HERE";
      };
    };
    paperless = {
      description = "Paperless-ngx document management configuration";
      keys = {
        PAPERLESS_DBENGINE = "postgresql";
        PAPERLESS_DBHOST = "10.255.0.11";
        PAPERLESS_DBPORT = "1024";
        PAPERLESS_DBNAME = "paperless";
        PAPERLESS_DBUSER = "paperless";
        PAPERLESS_DBPASS = "PLACE DB PASSWORD HERE";
        PAPERLESS_REDIS = "redis://10.255.0.11:1025/1";
        PAPERLESS_URL = "https://paperless.reinitialized.me";
        PAPERLESS_SECRET_KEY = "PLACE SECRET KEY HERE";
        PAPERLESS_ADMIN_USER = "admin";
        PAPERLESS_ADMIN_PASSWORD = "PLACE ADMIN PASSWORD HERE";
        PAPERLESS_ADMIN_MAIL = "admin@reinitialized.net";
        PAPERLESS_OCR_LANGUAGE = "eng";
        PAPERLESS_TIME_ZONE = "America/Chicago";
      };
    };
    pelican = {
      description = "Pelican Panel game server management configuration";
      keys = {
        APP_ENV = "production";
        APP_URL = "https://game.admin.reinitialized.net";
        APP_KEY = "base64:PLACE GENERATED APP KEY HERE";
        DB_CONNECTION = "pgsql";
        DB_HOST = "10.255.0.11";
        DB_PORT = "1024";
        DB_DATABASE = "pelican";
        DB_USERNAME = "pelican";
        DB_PASSWORD = "PLACE DB PASSWORD HERE";
        CACHE_STORE = "redis";
        REDIS_HOST = "10.255.0.11";
        REDIS_PORT = "1025";
        REDIS_DB = "2";
        SESSION_DRIVER = "redis";
        QUEUE_CONNECTION = "redis";
      };
    };

    ocis = {
      description = "ownCloud Infinite Scale cloud storage configuration (OIDC via Authentik)";
      keys = {
        # Core settings
        OCIS_URL = "https://cloud.reinitialized.net";
        OCIS_DOMAIN = "cloud.reinitialized.net";
        OCIS_LOG_LEVEL = "info";
        HTTP_PROTOCOL = "https";

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
        PROXY_CSP_CONFIG_FILE_LOCATION = "/etc/ocis/csp.yaml";
        PROXY_OIDC_ACCESS_TOKEN_VERIFY_METHOD = "none";

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
        PROXY_ROLE_ASSIGNMENT_OIDC_CLAIM = "groups";

        # Admin password (used only during ocis init for initial admin user)
        IDM_ADMIN_PASSWORD = "PLACE_ADMIN_PASSWORD_HERE";
      };
    };
  };
}
