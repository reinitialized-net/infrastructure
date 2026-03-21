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
  };
}
