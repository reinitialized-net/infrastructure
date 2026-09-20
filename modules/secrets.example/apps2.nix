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

    unifi = {
      description = "UniFi Network Controller MongoDB credentials";
      # Provision two root-owned mode-0600 runtime files before activation:
      # /var/lib/service-secrets/unifi-mongodb.env uses
      # MONGO_INITDB_ROOT_USERNAME and MONGO_INITDB_ROOT_PASSWORD.
      # /var/lib/service-secrets/unifi.env uses the five keys below.
      keys = {
        MONGO_USER = "unifi";
        MONGO_PASS = "YOUR_SECURE_PASSWORD_HERE";
        MONGO_PORT = "27017";
        MONGO_DBNAME = "unifi";
        MONGO_AUTHSOURCE = "admin";
      };
    };

    pgAdmin4 = {
      # Optional root-owned runtime env file; omit duplicate keys below when used.
      # file = "/var/lib/service-secrets/pgAdmin4.env";
      description = "pgAdmin4 web interface configuration";
      keys = {
        PGADMIN_DEFAULT_EMAIL = "admin@example.com";
        PGADMIN_DEFAULT_PASSWORD = "YOUR_SECURE_PASSWORD_HERE";
      };
    };

    volumeMigration = {
      description = "SSH private key for docker volume migration between hosts";
      file = lib.mkDefault "/var/lib/service-secrets/docker-volume-migration.key";
    };

    redisInsight = {
      # Optional root-owned runtime env file; omit duplicate keys below when used.
      # file = "/var/lib/service-secrets/redisInsight.env";
      description = "Redis Insight configuration";
      keys = {
        RI_REDIS_HOST1 = "10.255.0.11";
        RI_REDIS_PORT1 = "1025";
        RI_REDIS_ALIAS1 = "valkey1";
      };
    };
    omniroute = {
      # Provision /var/lib/service-secrets/omniroute.env as root:root 0600 with:
      # JWT_SECRET=<openssl rand -base64 48>
      # API_KEY_SECRET=<openssl rand -hex 32>
      # STORAGE_ENCRYPTION_KEY=<openssl rand -hex 32>
      # INITIAL_PASSWORD=<dashboard admin password; change it after first login>
      description = "OmniRoute AI gateway configuration (secrets in runtime env file)";
      keys = {
        DATA_DIR = "/app/data";
        PORT = "20128";
        NEXT_PUBLIC_BASE_URL = "https://ai.reinitialized.net";
        AUTH_COOKIE_SECURE = "true";
        # Reject unauthenticated /v1 requests; keys are issued from the dashboard.
        REQUIRE_API_KEY = "true";
        ALLOW_API_KEY_REVEAL = "false";
        # Live dashboard WebSocket is proxied by rp1 at /live-ws.
        LIVE_WS_HOST = "0.0.0.0";
        LIVE_WS_PORT = "20132";
        LIVE_WS_ALLOWED_ORIGINS = "https://ai.reinitialized.net";
        NEXT_PUBLIC_LIVE_WS_PUBLIC_URL = "wss://ai.reinitialized.net/live-ws";
        # Allow RFC1918 provider URLs so the ai1 llama.cpp API can be added as a provider.
        OMNIROUTE_ALLOW_PRIVATE_PROVIDER_URLS = "true";
        # V8 heap; keep below the container --memory limit in hosts/apps2.nix.
        OMNIROUTE_MEMORY_MB = "2048";
        JWT_SECRET = "PLACE JWT SECRET HERE";
        API_KEY_SECRET = "PLACE API KEY SECRET HERE";
        STORAGE_ENCRYPTION_KEY = "PLACE STORAGE ENCRYPTION KEY HERE";
        INITIAL_PASSWORD = "PLACE INITIAL DASHBOARD PASSWORD HERE";
      };
    };
    forgejoRunner = {
      # Provision /var/lib/service-secrets/forgejo-runner.env as root:root 0600.
      description = "Forgejo Runner CI/CD configuration";
      keys = {
        FORGEJO_INSTANCE_URL = "PLACE FORGEJO INSTANCE URL HERE";
        FORGEJO_RUNNER_REGISTRATION_TOKEN = "PLACE REGISTRATION TOKEN HERE";
        FORGEJO_RUNNER_NAME = "runner-1";
        FORGEJO_RUNNER_LABELS = "docker:docker://node:20-bookworm";
        FORGEJO_RUNNER_CAPACITY = "2";
        FORGEJO_RUNNER_FETCH_TIMEOUT = "10s";
        FORGEJO_RUNNER_FETCH_INTERVAL = "5s";
      };
    };
  };
}
