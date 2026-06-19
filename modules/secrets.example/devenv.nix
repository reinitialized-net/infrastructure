{
  lib,
  ...
}: {
  secrets = {
    meshNetwork = {
      description = "MeshNetwork secrets";
      file = lib.mkDefault (builtins.toFile "mesh-privatekey" "PLACE PRIVATE KEY HERE");
    };
    opnsenseFirewall = {
      description = "OPNsense firewall API credentials";
      file = lib.mkDefault /run/secrets/opnsense-api-secret;
      keys = {
        host = "OPNSENSE_HOST_OR_IP";
        port = "443";
        apiKey = "PLACE_API_KEY_HERE";
        apiSecret = "PLACE_API_SECRET_HERE";
      };
    };
    infraAutomation = {
      description = "Forgejo bot credentials and metadata for automated infrastructure updates";
      file = lib.mkDefault /run/secrets/infra-automation-token;
      keys = {
        forgejoBaseUrl = "https://git.ds.reinitialized.net";
        repoOwner = "reinitialized.net";
        repoName = "infrastructure";
        repoCloneUrl = "https://git.ds.reinitialized.net/reinitialized.net/infrastructure.git";
        defaultBranch = "indev";
        secretsDir = "/var/lib/infratainer/secrets";
        issueLabels = "infra-auto-update";
        automationName = "Infratainer";
        forgejoUsername = "Infratainer";
        gitAuthorName = "Infratainer";
        gitAuthorEmail = "infratainer@reinitialized.net";
        renovateBranchPrefix = "renovate/";
      };
    };
    volumeMigration = {
      description = "SSH private key for docker volume migration between hosts";
      file = lib.mkDefault (builtins.toFile "volume-migration-key" "PLACE PRIVATE KEY HERE");
    };
  };
}
