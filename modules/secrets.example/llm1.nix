{
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
    llmApi = {
      description = "Strata API keys, one per line (# comments allowed)";
      file = lib.mkDefault "/var/lib/service-secrets/llm-api-keys";
    };
  };
}
