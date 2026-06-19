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
    infraAutomation = {
      description = "Forgejo bot credentials and metadata for automated infrastructure update failure reporting";
      file = lib.mkDefault /run/secrets/infra-automation-token;
      keys = {
        forgejoBaseUrl = "https://git.ds.reinitialized.net";
        repoOwner = "reinitialized.net";
        repoName = "infrastructure";
        issueLabels = "infra-auto-update";
      };
    };
    acmeDns = {
      description = "Technitium DNS API token for ACME DNS-01 challenges";
      file = lib.mkDefault (builtins.toFile "acme-dns-token" ''
        TECHNITIUM_API_TOKEN=${config.secrets.acmeDns.keys.apiToken}
        TECHNITIUM_SERVER_BASE_URL=http://10.255.0.3:1026/
      '');
      keys = {
        apiToken = "PLACE API TOKEN HERE";
      };
    };

    unifi = {
      description = "UniFi Network Controller MongoDB credentials";
      keys = {
        MONGO_USER = "unifi";
        MONGO_PASS = "YOUR_SECURE_PASSWORD_HERE";
        MONGO_PORT = "27017";
        MONGO_DBNAME = "unifi";
        MONGO_AUTHSOURCE = "admin";
      };
    };

    pgAdmin4 = {
      description = "pgAdmin4 web interface configuration";
      keys = {
        PGADMIN_DEFAULT_EMAIL = "admin@example.com";
        PGADMIN_DEFAULT_PASSWORD = "YOUR_SECURE_PASSWORD_HERE";
      };
    };

    volumeMigration = {
      description = "SSH private key for docker volume migration between hosts";
      file = lib.mkDefault (builtins.toFile "volume-migration-key" "PLACE PRIVATE KEY HERE");
    };

    redisInsight = {
      description = "Redis Insight configuration";
      keys = {
        RI_REDIS_HOST1 = "10.255.0.11";
        RI_REDIS_PORT1 = "1025";
        RI_REDIS_ALIAS1 = "valkey1";
      };
    };
    forgejoRunner = {
      description = "Forgejo Runner CI/CD configuration";
      keys = {
        FORGEJO_INSTANCE_URL = "PLACE FORGEJO INSTANCE URL HERE";
        FORGEJO_RUNNER_REGISTRATION_TOKEN = "PLACE REGISTRATION TOKEN HERE";
        FORGEJO_RUNNER_NAME = "runner-1";
        FORGEJO_RUNNER_LABELS = "docker:docker://node:20-bookworm";
        FORGEJO_RUNNER_CAPACITY = "2";
        FORGEJO_RUNNER_FETCH_TIMEOUT = "10s";
        FORGEJO_RUNNER_FETCH_INTERVAL = "5s";
        # Admin API token for clean re-registration (prevents duplicate runner entries).
        # Generate at: Forgejo > Settings > Applications > API Token (requires admin user).
        FORGEJO_ADMIN_API_TOKEN = "PLACE FORGEJO ADMIN API TOKEN HERE";
      };
    };
  };
}
