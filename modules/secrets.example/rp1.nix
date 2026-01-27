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
      description = "SSH private key for certificate distribution to apps1/apps2";
      # Generate with: ssh-keygen -t ed25519 -f /root/.ssh/id_cert_distribution -N ""
      # The public key should be added to apps1/apps2 secrets.certDistribution.keys.sshPublicKey
      file = lib.mkDefault (builtins.toFile "cert-distribution-key" ''
        -----PLACE PRIVATE KEY HERE-----
      '');
    };
  };
}
