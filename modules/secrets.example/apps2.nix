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
    volumeMigration = {
      description = "SSH private key for docker volume migration between hosts";
      file = lib.mkDefault (builtins.toFile "volume-migration-key" "PLACE PRIVATE KEY HERE");
    };

    redisInsight = {
      description = "Redis Insight configuration";
      keys = {
        RI_REDIS_HOST1 = "VALKEY_MESH_IP";
        RI_REDIS_PORT1 = "VALKEY_MESH_PORT";
        RI_REDIS_ALIAS1 = "valkey1";
      };
    };
  };
}