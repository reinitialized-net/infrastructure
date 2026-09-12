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
