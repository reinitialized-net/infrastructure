{
  lib,
  ...
}: {
  secrets = {
    meshNetwork = {
      description = "MeshNetwork secrets";
      file = lib.mkDefault (builtins.toFile "mesh-privatekey" "PLACE PRIVATE KEY HERE");
    };
    opnsenseFirewall = {
      description = "OPNsense firewall API credentials";
      file = lib.mkDefault /run/secrets/opnsense-api-secret;
      keys = {
        host = "OPNSENSE_HOST_OR_IP";
        port = "443";
        apiKey = "PLACE_API_KEY_HERE";
        apiSecret = "PLACE_API_SECRET_HERE";
      };
    };
    volumeMigration = {
      description = "SSH private key for docker volume migration between hosts";
      file = lib.mkDefault (builtins.toFile "volume-migration-key" "PLACE PRIVATE KEY HERE");
    };
  };
}
