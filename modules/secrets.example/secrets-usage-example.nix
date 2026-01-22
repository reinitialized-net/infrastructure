# Example: Using the generalized secrets system
{
  lib,
  config,
  ...
}: {
  # Define secrets using the new generalized system
  secrets = {
    # Mesh network secrets
    mesh-network = {
      description = "Wireguard mesh network credentials";
      file = builtins.toFile "mesh-privatekey" "YourBase64PrivateKeyHere==";
      keys = {
        nodeId = 1;
        listenPort = 51820;
        peers = [
          {
            nodeId = 2;
            publicKey = "Base64PublicKeyForNode2==";
            endpoint = "192.168.1.100:51820";
            persistentKeepalive = 25;
          }
        ];
      };
    };

    # Hudu application secrets
    hudu = {
      description = "Hudu documentation platform credentials";
      keys = {
        SECRET_KEY_BASE = "783471e6e7f1e100e19f4c9898e679ea308d017efbf3f5eff69ffca663dfdff043d90d066dddcf584cee537bd6cbcc6957e1373567f8ebf1450b35c361074575";
        PASSWORD_KEY = "640f83885bbbb4b376b2fcd6f5ddc1cc";
        DOMAIN = "docs.example.com";
        URL = "example.com";
        DB_HOST = "postgres1";
        DB_USERNAME = "postgres";
        DB_PASSWORD = "";
        SMTP_ADDRESS = "smtp.example.com";
        SMTP_PORT = "587";
      };
    };

    # API service secrets
    api-service = {
      description = "External API credentials";
      keys = {
        apiKey = "your-api-key-here";
        endpoint = "https://api.example.com";
        timeout = 30;
        retries = 3;
      };
    };

    # Certificate secrets
    ssl-cert = {
      description = "SSL certificate and key";
      file = /path/to/cert.pem;
      keys = {
        certPath = "/etc/ssl/certs/mycert.pem";
        keyPath = "/etc/ssl/private/mykey.pem";
      };
    };
  };

  # Now use the secrets in your service configurations
  services.meshNetwork = lib.mkIf (config.secrets ? mesh-network) {
    enable = true;
    nodeId = config.secrets.mesh-network.keys.nodeId;
    listenPort = config.secrets.mesh-network.keys.listenPort;
    privateKeyFile = config.secrets.mesh-network.file;
    peers = config.secrets.mesh-network.keys.peers;
  };
}
