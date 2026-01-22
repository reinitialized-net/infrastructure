# modules/profiles/secrets.nix
## Generalized secrets management system
{ lib, config, ... }:
let
  cfg = config.secrets;
in
{
  options.secrets = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        keys = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = {};
          description = ''
            Key-value pairs for this secret.
            Keys can be any string, values can be any Nix type.
          '';
          example = lib.literalExpression ''
            {
              apiKey = "secret-api-key";
              endpoint = "https://api.example.com";
              timeout = 30;
            }
          '';
        };

        file = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Path to a file containing this secret.
            Useful for private keys, certificates, etc.
          '';
          example = "/run/secrets/private-key";
        };

        description = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Human-readable description of this secret.";
        };
      };
    });
    default = {};
    description = ''
      Centralized secrets management.
      Each secret can contain custom key-value pairs and/or a file path.
    '';
    example = lib.literalExpression ''
      {
        mesh-network = {
          description = "Wireguard mesh network credentials";
          file = /run/secrets/mesh-privatekey;
          keys = {
            nodeId = 1;
            listenPort = 51820;
          };
        };
        
        api-service = {
          description = "External API credentials";
          keys = {
            apiKey = "your-api-key";
            endpoint = "https://api.example.com";
            timeout = 30;
          };
        };
      }
    '';
  };

  config = {
    # Assertions to validate secret configurations
    assertions = lib.flatten (lib.mapAttrsToList (name: secret:
      let
        hasKeys = secret.keys != {};
        hasFile = secret.file != null;
      in
      [
        {
          assertion = hasKeys || hasFile;
          message = "Secret '${name}' must define either 'keys' or 'file' (or both).";
        }
      ]
    ) cfg);
  };
}
