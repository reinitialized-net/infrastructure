{
  lib,
  ...
}: {
  secrets = {
    meshNetwork = {
      description = "MeshNetwork secrets";
      file = lib.mkDefault (builtins.toFile "mesh-privatekey" "PLACE PRIVATE KEY HERE");
    };

    acmeDns = {
      description = "Technitium DNS API credentials for ACME DNS-01 challenge";
      file = lib.mkDefault (builtins.toFile "acme-dns-credentials" ''
        TECHNITIUM_SERVER_BASE_URL=http://TECHNITIUM_HOST:5380
        TECHNITIUM_API_TOKEN=PLACE_API_TOKEN_HERE
      '');
      keys = {
        apiToken = "PLACE_API_TOKEN_HERE";
      };
    };
    volumeMigration = {
      description = "SSH private key for docker volume migration between hosts";
      file = lib.mkDefault (builtins.toFile "volume-migration-key" "PLACE PRIVATE KEY HERE");
    };
  };
}
