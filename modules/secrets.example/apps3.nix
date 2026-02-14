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
    conduwuit = {
      description = "Conduwuit Matrix homeserver configuration";
      keys = {
        CONDUWUIT_SERVER_NAME = "matrix.reinitialized.net";
        CONDUWUIT_ADDRESS = "0.0.0.0";
        CONDUWUIT_PORT = "8008";
        CONDUWUIT_DATABASE_PATH = "/var/lib/conduwuit";
        CONDUWUIT_ALLOW_REGISTRATION = "false";
        CONDUWUIT_ALLOW_FEDERATION = "false";
        CONDUWUIT_TRUSTED_SERVERS = "[]";
        CONDUWUIT_LOG = "warn,state_res=warn";
        CONDUWUIT_MAX_REQUEST_SIZE = "104857600";
        CONDUWUIT_REGISTRATION_TOKEN = "PLACE REGISTRATION TOKEN HERE";
      };
    };
  };
}
