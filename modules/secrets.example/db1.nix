{
  config,
  lib,
  ...
}:
{
  secrets = {
    # Provision private-key files separately before services start on every boot.
    # Keep these persistent paths root-owned and inaccessible to other users.
    meshNetwork = {
      description = "MeshNetwork WireGuard private key";
      file = lib.mkDefault "/var/lib/wireguard/wg-mesh.key";
    };
    infraAutomation = {
      description = "Forgejo bot credentials and metadata for automated infrastructure update failure reporting";
      file = lib.mkDefault "/var/lib/infratainer/secrets/infra-automation-token";
      keys = {
        forgejoBaseUrl = "https://git.ds.reinitialized.net";
        repoOwner = "reinitialized.net";
        repoName = "infrastructure";
        issueLabels = "infra-auto-update";
      };
    };

    postgres1 = {
      # Optional root-owned runtime env file; omit duplicate keys below when used.
      # file = "/var/lib/service-secrets/postgres1.env";
      keys = {
        POSTGRES_USER = "rnetadmin";
        POSTGRES_PASSWORD = "PLACE_GENERATED_POSTGRES_PASSWORD_HERE"; # Initial setup only
      };
    };
    volumeMigration = {
      description = "SSH private key for docker volume migration between hosts";
      file = lib.mkDefault "/var/lib/service-secrets/docker-volume-migration.key";
    };
  };
}
