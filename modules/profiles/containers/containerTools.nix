{
  lib,
  pkgs,
  ...
}: let
  # Helper function to create a script from a file (no substitution needed for bash-only scripts)
  makeToolScript = name: scriptPath:
    pkgs.writeScriptBin name (builtins.readFile scriptPath);
  
  # Load all .sh files from tools directory
  toolsDir = ./tools;
  scriptFiles = builtins.attrNames (builtins.readDir toolsDir);
  
  # Filter for .sh files and create script derivations
  toolScripts = map (filename:
    let
      scriptName = lib.removeSuffix ".sh" filename;
      scriptPath = "${toolsDir}/${filename}";
    in
      makeToolScript scriptName scriptPath
  ) (builtins.filter (name: lib.hasSuffix ".sh" name) scriptFiles);
in {
  environment.systemPackages = toolScripts;
}
