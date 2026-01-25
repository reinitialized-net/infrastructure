{
  lib,
  pkgs,
  config,
  ...
}: let
  meshEnabled = config.services.meshNetwork.enable or false;
  
  # Helper function to create a script with package substitution
  makeToolScript = name: scriptPath: substitutions:
    let
      # Read the script file
      scriptContent = builtins.readFile scriptPath;
      # Replace @package@ style placeholders with actual paths
      replacedContent = lib.replaceStrings
        (map (key: "@${key}@") (builtins.attrNames substitutions))
        (builtins.attrValues substitutions)
        scriptContent;
    in
      pkgs.writeScriptBin name replacedContent;
  
  # Load and process each tool script
  toolScripts = with pkgs; [
    (makeToolScript "mesh-keygen" ./tools/mesh-keygen.sh {
      wireguard-tools = "${wireguard-tools}";
    })
    
    (makeToolScript "mesh-status" ./tools/mesh-status.sh {})
    
    (makeToolScript "mesh-test" ./tools/mesh-test.sh {
      wireguard-tools = "${wireguard-tools}";
      iputils = "${iputils}";
    })
  ];
in {
  environment.systemPackages = lib.mkIf meshEnabled toolScripts;
}
