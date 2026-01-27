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
      description = "SSH public key for certificate distribution from rp1";
      keys = {
        sshPublicKey = "ssh-ed25519 AAAA... rp1-cert-distribution";
      };
    };
    
    hudu = {
      description = "Hudu secrets";
      keys = {
        SECRET_KEY_BASE = "783471e6e7f1e100e19f4c9898e679ea308d017efbf3f5eff69ffca663dfdff043d90d066dddcf584cee537bd6cbcc6957e1373567f8ebf1450b35c361074575";
        PASSWORD_KEY = "640f83885bbbb4b376b2fcd6f5ddc1cc";
        DOMAIN = "docs.example.com";
        URL = "example.com";
        SUBDOMAINS = "docs";
        TWO_FACTOR_KEY = "761ee57449c16ae2e32ef22a6442101b";

        PUID = "1000";
        PGID = "1000";
        ONLY_SUBDOMAINS = "true";
        VALIDATION = "http";
        STAGING = "false";
        DISABLE_SSL = "true";

        DB_HOST = "postgres1";
        DB_USERNAME = "postgres";
        DB_PASSWORD = "";
        DB_NAME = "hudu_production";
        POSTGRES_HOST_AUTH_METHOD = "trust";

        SMTP_DOMAIN = "smtp.example.com";
        SMTP_ADDRESS = "smtp.example.com";
        SMTP_PORT = "587";
        SMTP_STARTTLS_AUTO = "true";
        SMTP_USERNAME = "";
        SMTP_PASSWORD = "";
        SMTP_AUTHENTICATION = "login";
        SMTP_OPENSSL_VERIFY_MODE = "none";
        SMTP_FROM_ADDRESS = "";

        USE_LOCAL_FILESYSTEM = "true";
        AUTHENTICATE_UPLOADS = "true";

        RAILS_ENV = "production";
        RACK_ENV = "production";
        RAILS_MAX_THREADS = "50";

        REDIS_URL = "redis://redis1";
      };
    };
  };
}