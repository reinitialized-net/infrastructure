{
  config,
  lib,
  ...
}: {
  secrets = {
    meshNetwork = {
      description = "MeshNetwork secrets";
      file = lib.mkDefault (builtins.toFile "mesh-privatekey" "REPLACE_WITH_ACTUAL_MESH_PRIVATE_KEY");
    };
    openclaw = {
      description = "OpenClaw configuration";
      file = lib.mkDefault (builtins.toFile "openclaw.json" ''
        {
          "botToken": "REPLACE_WITH_BOT_TOKEN",
          "modelProvider": {
            "apiKey": "REPLACE_WITH_API_KEY"
          }
        }
      '');
    };
  };
}