{
  self,
  lib,
  pkgs,
  config,
  ...
}: let
  # Import mesh topology for host IP resolution
  meshTopology = import "${self}/modules/profiles/meshNetwork/meshTopology.nix" { inherit lib; };

  # OPNsense secrets from the secrets module
  opnsenseSecrets = config.secrets.opnsenseFirewall or {};
  opnsenseKeys = opnsenseSecrets.keys or {};
  opnsenseSecretFile = if opnsenseSecrets ? file && opnsenseSecrets.file != null
    then toString opnsenseSecrets.file
    else "/run/secrets/opnsense-api-secret";

  # Get list of valid hostnames from mesh topology
  validHosts = builtins.attrNames meshTopology.nodes;
  validHostsStr = lib.concatStringsSep " " validHosts;

  # Create a lookup table of hostname -> IP address (extracted from endpoint)
  # The endpoint format is "IP:PORT", we extract just the IP
  hostIpMap = lib.mapAttrs (name: node:
    if node ? endpoint
    then lib.head (lib.splitString ":" node.endpoint)
    else null
  ) meshTopology.nodes;

  # Generate case statements for host IP lookup
  hostIpCases = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: ip:
      if ip != null
      then "      ${name}) echo \"${ip}\" ;;"
      else "      ${name}) echo \"ERROR: Host '${name}' has no endpoint configured\" >&2; return 1 ;;"
    ) hostIpMap
  );

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
    (makeToolScript "rebuildHost" ./tools/rebuild-host.sh {
      validHosts = validHostsStr;
      hostIpCases = hostIpCases;
    })

    (makeToolScript "updateInfra" ./tools/update-infra.sh {
      validHosts = validHostsStr;
      hostIpCases = hostIpCases;
    })

    (makeToolScript "updateNetworkFirewallRules" ./tools/update-network-firewall-rules.sh {
      curl = "${curl}";
      jq = "${jq}";
      util-linux = "${util-linux}";
      coreutils = "${coreutils}";
      gawk = "${gawk}";
      gnugrep = "${gnugrep}";
      gnused = "${gnused}";
      secretsHost = opnsenseKeys.host or "";
      secretsPort = opnsenseKeys.port or "443";
      secretsApiKey = opnsenseKeys.apiKey or "";
      secretsApiSecret = opnsenseKeys.apiSecret or "";
      secretsApiSecretFile = opnsenseSecretFile;
    })
  ];
in {
  environment.systemPackages = toolScripts;
}
