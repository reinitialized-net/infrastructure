{
  lib,
  pkgs,
  ...
}: let
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
  
  # Load and process each tool script with required package substitutions
  toolScripts = with pkgs; [
    (makeToolScript "migrate-volumes" ./tools/migrate-volumes.sh {
      docker = "${docker}";
      coreutils = "${coreutils}";
      gawk = "${gawk}";
      openssh = "${openssh}";
      gnugrep = "${gnugrep}";
    })
  ];
in {
  environment.systemPackages = toolScripts;
}
