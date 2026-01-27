{
  lib,
  ...
}: {
  secrets = {
    meshNetwork = {
      description = "MeshNetwork secrets";
      file = lib.mkDefault (builtins.toFile "mesh-privatekey" "PLACE PRIVATE KEY HERE");
    };
    certDistribution = {
      description = "SSH public key for certdist service account (certificate distribution from rp1)";
      keys = {
        sshPublicKey = "ssh-ed25519 AAAA... rp1-cert-distribution";
      };
    };
  };
}