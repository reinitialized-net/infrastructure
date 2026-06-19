{
  config,
  lib,
  ...
}: {
  secrets = {
    meshNetwork = {
      description = "MeshNetwork WireGuard private key";
      file = lib.mkDefault (builtins.toFile "mesh-privatekey" "PRIVATE KEY HERE");
    };
    infraAutomation = {
      description = "Forgejo bot credentials and metadata for automated infrastructure update failure reporting";
      file = lib.mkDefault /run/secrets/infra-automation-token;
      keys = {
        forgejoBaseUrl = "https://git.ds.reinitialized.net";
        repoOwner = "reinitialized.net";
        repoName = "infrastructure";
        issueLabels = "infra-auto-update";
      };
    };

    postgres1 = {
      keys = {
        POSTGRES_USER = "rnetadmin";
        POSTGRES_PASSWORD = "rnetadmin";  # Initial setup only
      };
    };
    volumeMigration = {
      description = "SSH private key for docker volume migration between hosts";
      file = lib.mkDefault (builtins.toFile "volume-migration-key" ''
        -----BEGIN OPENSSH PRIVATE KEY-----
        PRIVATE KEY HERE
        -----END OPENSSH PRIVATE KEY-----
      '');
    };
  };
}
