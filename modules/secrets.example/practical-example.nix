# Practical example: Using the secrets system in a real configuration
# Copy this to modules/secrets/ and customize for your needs
{
  lib,
  config,
  ...
}: {
  # Import the optional integration module for automatic service wiring
  imports = [ ../profiles/secrets-integration.nix ];

  secrets = {
    # Mesh network credentials
    mesh-network = {
      description = "Wireguard mesh network for Docker container networking";
      file = builtins.toFile "mesh-privatekey" "REPLACE_WITH_ACTUAL_PRIVATE_KEY";
      keys = {
        nodeId = 1;  # Change this for each node (1-254)
        listenPort = 51820;
        peers = [
          {
            nodeId = 2;
            publicKey = "PEER_2_PUBLIC_KEY_HERE";
            endpoint = "192.168.1.100:51820";
            persistentKeepalive = 25;
          }
          # Add more peers as needed
        ];
      };
    };

    # Hudu documentation platform
    hudu = {
      description = "Hudu IT documentation credentials and configuration";
      keys = {
        # Application secrets
        SECRET_KEY_BASE = "generate_with_rake_secret";
        PASSWORD_KEY = "generate_random_32_chars";
        TWO_FACTOR_KEY = "generate_random_32_chars";
        
        # Domain configuration
        DOMAIN = "docs.example.com";
        URL = "example.com";
        SUBDOMAINS = "docs";
        
        # Database
        DB_HOST = "postgres1";
        DB_USERNAME = "postgres";
        DB_PASSWORD = "your_db_password";
        DB_NAME = "hudu_production";
        
        # SMTP
        SMTP_ADDRESS = "smtp.example.com";
        SMTP_PORT = "587";
        SMTP_USERNAME = "notifications@example.com";
        SMTP_PASSWORD = "your_smtp_password";
        SMTP_DOMAIN = "example.com";
        
        # Storage
        USE_LOCAL_FILESYSTEM = "true";
        AUTHENTICATE_UPLOADS = "true";
      };
    };

    # Additional service secrets can be added here
    backup = {
      description = "Backup service credentials";
      keys = {
        s3Bucket = "my-backups";
        s3AccessKey = "AWS_ACCESS_KEY";
        s3SecretKey = "AWS_SECRET_KEY";
        encryption = {
          enabled = true;
          passphrase = "backup-encryption-passphrase";
        };
      };
    };
  };

  # Services are automatically configured via secrets-integration.nix
  # But you can also manually reference secrets:
  
  # Enable mesh network (auto-configured from secrets)
  services.meshNetwork.enable = true;

  # Use Hudu secrets in your Docker compose or service
  # environment.variables = config.secrets.hudu.keys;

  # Use backup secrets
  # services.backup = {
  #   enable = true;
  #   s3 = config.secrets.backup.keys;
  # };
}
