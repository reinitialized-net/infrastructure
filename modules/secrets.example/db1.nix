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

    pgAdmin4 = {
      description = "pgAdmin4 secrets";
      keys = {
        PGADMIN_DEFAULT_EMAIL = "EMAIL HERE";
        PGADMIN_DEFAULT_PASSWORD = "PASSWORD HERE";
      };
    };

    postgres1 = {
      keys = {
        POSTGRES_USER = "changeMe";
        POSTGRES_PASSWORD = "changeMe";  # Initial setup only
      };
    };
    volumeMigration = {
      description = "SSH private key for docker volume migration between hosts";
      file = lib.mkDefault (builtins.toFile "volume-migration-key" "PLACE PRIVATE KEY HERE");
    };
  };
}