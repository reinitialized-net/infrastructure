# modules/profiles/secrets-integration.nix
## Optional module that integrates the secrets system with existing services
## Import this to automatically wire up secrets to services
{ lib, config, ... }:
let
  cfg = config.secrets;
in
{
  config = {
    # Auto-configure meshNetwork from secrets if defined
    services.meshNetwork = lib.mkIf (cfg ? mesh-network && cfg.mesh-network.keys ? nodeId) {
      nodeId = lib.mkDefault cfg.mesh-network.keys.nodeId;
      listenPort = lib.mkDefault (cfg.mesh-network.keys.listenPort or 51820);
      privateKeyFile = lib.mkDefault cfg.mesh-network.file;
      peers = lib.mkDefault (cfg.mesh-network.keys.peers or []);
    };

    # Example: You can add more service integrations here
    # services.yourService = lib.mkIf (cfg ? your-service) {
    #   apiKey = cfg.your-service.keys.apiKey;
    # };
  };
}
