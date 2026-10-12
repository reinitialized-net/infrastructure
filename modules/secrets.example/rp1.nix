{
  lib,
  ...
}: {
  secrets = {
    # Provision private-key files separately before services start on every boot.
    # Keep these persistent paths root-owned and inaccessible to other users.
    meshNetwork = {
      description = "MeshNetwork secrets";
      file = lib.mkDefault "/var/lib/wireguard/wg-mesh.key";
    };

    infraAutomation = {
      description = "Forgejo token for automated infrastructure update failure reporting";
      file = lib.mkDefault "/var/lib/infratainer/secrets/infra-automation-token";
      keys = {
        forgejoBaseUrl = "https://git.ds.reinitialized.net";
        repoOwner = "reinitialized.net";
        repoName = "infrastructure";
        issueLabels = "infra-auto-update";
      };
    };

    acmeDns = {
      description = "Technitium DNS credentials for ACME";
      # Provision this root-owned file (0600) separately. It must contain:
      # TECHNITIUM_API_TOKEN=<token>
      # TECHNITIUM_SERVER_BASE_URL=http://10.255.0.3:1026/
      file = lib.mkDefault "/var/lib/service-secrets/acme-dns.env";
    };
    llmLanKey = {
      description = "Strata API key rp1 sends for internal clients of llm.in";
      # Provision this root-owned nginx snippet (0640 root:nginx) separately, with
      # one of llm1's API keys:
      # set $llm_lan_auth "Bearer <key>";
      file = lib.mkDefault "/var/lib/service-secrets/llm-lan-auth.conf";
    };
    volumeMigration = {
      description = "SSH private key for docker volume migration between hosts";
      file = lib.mkDefault "/var/lib/service-secrets/docker-volume-migration.key";
    };
  };
}
