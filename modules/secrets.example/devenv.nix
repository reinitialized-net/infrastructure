{
  lib,
  ...
}: {
  # Example mesh network configuration
  # Copy this to modules/secrets/mesh.nix and customize with your actual keys

  secrets.meshNetwork = {
    description = "Wireguard mesh network credentials and configuration";
    
    # Path to the Wireguard private key file
    # Generate with: wg genkey > privatekey
    file = lib.mkDefault (builtins.toFile "mesh-privatekey" "YourBase64PrivateKeyHere==");

    keys = {
      # Unique node ID (1-254) for this mesh member
      nodeId = 1;
      
      # Wireguard listen port (optional, defaults to 51820)
      listenPort = 51820;
      
      # List of mesh network peers
      # Define all other nodes in your mesh network
      peers = [
        {
          nodeId = 2;  # Must be unique, range 1-254
          publicKey = "Base64PublicKeyForNode2==";
          endpoint = "node2.example.com:51820";  # Public IP/hostname with port
          persistentKeepalive = 25;  # Keep NAT alive
        }
        {
          nodeId = 3;
          publicKey = "Base64PublicKeyForNode3==";
          endpoint = "192.168.1.100:51820";
          persistentKeepalive = 25;
        }
        {
          nodeId = 4;
          publicKey = "Base64PublicKeyForNode4==";
          endpoint = null;  # Set to null if behind NAT without port forwarding
          persistentKeepalive = 25;
        }
        # Add more peers as needed...
      ];
    };
  };
}
