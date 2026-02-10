{
  config,
  lib,
  ...
}: {
    meshNetwork = {
      file = lib.mkDefault (builtins.toFile "mesh-privatekey" "PRIVATE KEY HERE");
    };

    postgres1 = {
      keys = {
        POSTGRES_USER = "rnetadmin";
        POSTGRES_PASSWORD = "rnetadmin";  # Initial setup only
      };
    };
    volumeMigration = {
      description = "SSH private key for docker volume migration between hosts";
      file = lib.mkDefault (builtins.toFile "volume-migration-key" ''
        -----BEGIN OPENSSH PRIVATE KEY-----
        PRIVATE KEY HERE
        -----END OPENSSH PRIVATE KEY-----
      '');
    };
}