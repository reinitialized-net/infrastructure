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
      sudo = "${sudo}";
      coreutils = "${coreutils}";
      gawk = "${gawk}";
      gzip = "${gzip}";
      bzip2 = "${bzip2}";
      xz = "${xz}";
      openssh = "${openssh}";
      gnugrep = "${gnugrep}";
    })
  ];
in {
  environment.systemPackages = toolScripts;
}
