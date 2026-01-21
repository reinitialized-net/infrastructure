{
  lib,
  ...
}: {
  # Example mesh network configuration
  # Copy this to modules/secrets/mesh.nix and customize with your actual keys

  services.meshNetwork = {
    # Generate a private key for this node:
    # wg genkey > /path/to/privatekey
    # 
    # Then reference it here:
    privateKeyFile = lib.mkDefault (builtins.toFile "mesh-privatekey" "YourBase64PrivateKeyHere==");

    # Define all other nodes in your mesh network
    peers = lib.mkDefault [
      {
        nodeId = 1;  # Must be unique, range 1-254
        publicKey = "Base64PublicKeyForNode1==";
        endpoint = "node1.example.com:51820";  # Public IP/hostname with port
        persistentKeepalive = 25;  # Keep NAT alive
      }
      {
        nodeId = 2;
        publicKey = "Base64PublicKeyForNode2==";
        endpoint = "192.168.1.100:51820";
        persistentKeepalive = 25;
      }
      {
        nodeId = 3;
        publicKey = "Base64PublicKeyForNode3==";
        endpoint = null;  # Set to null if behind NAT without port forwarding
        persistentKeepalive = 25;
      }
      # Add more peers as needed...
    ];
  };
}
