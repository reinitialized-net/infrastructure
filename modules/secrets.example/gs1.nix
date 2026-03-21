{
  config,
  lib,
  ...
}: {
  secrets = {
    meshNetwork = {
      description = "MeshNetwork WireGuard private key";
      file = lib.mkDefault (builtins.toFile "mesh-privatekey" "PLACE PRIVATE KEY HERE");
    };
    volumeMigration = {
      description = "SSH private key for Docker volume migration between hosts";
      file = lib.mkDefault (builtins.toFile "volume-migration-key" "PLACE PRIVATE KEY HERE");
    };
    wings = {
      description = ''
        Pelican Wings daemon configuration (config.yml).
        Generate from: Panel → Nodes → [gs1] → Configuration tab → copy YAML.
      '';
      file = lib.mkDefault (builtins.toFile "wings-config.yml" ''
        # Replace this entire file with the YAML from:
        # Pelican Panel → Nodes → [gs1] → Configuration
        debug: false
        api:
          host: 0.0.0.0
          port: 8080
          ssl:
            enabled: false
        system:
          data: /var/lib/pelican/volumes
        token: PLACE_TOKEN_FROM_PANEL_HERE
        token_id: PLACE_TOKEN_ID_FROM_PANEL_HERE
        panel_location: https://game.admin.reinitialized.net
      '');
    };
  };
}
