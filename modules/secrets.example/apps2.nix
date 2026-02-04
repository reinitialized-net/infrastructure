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
      description = "Technitium DNS API token for ACME DNS-01 challenges";
      keys = {
        apiToken = "YOUR_TECHNITIUM_API_TOKEN_HERE";
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
  };
}