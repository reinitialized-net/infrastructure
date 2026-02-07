{
  config,
  ...
}:{
  # Networking Configuration
  networking = {
    hostName = "apps1";
    useDHCP = false;
  };
  systemd.network.networks = {
    "eth0" = {
      address = [
        "10.1.11.2/24"
      ];
      dns = [
        "10.1.11.2"
        "10.1.11.3"
      ];
      ntp = [
        "10.1.11.1"
      ];
      gateway = [
        "10.1.11.1"
      ];
      matchConfig.Path = "pci-0000:06:12.0";
    };
  };
  # Configure MeshNetwork
  services.meshNetwork = {
      enable = true;
  };
  # ACME certificate generation for Technitium DNS (dnsOne)
  # Generates certificate with PKCS#12 for direct use by Technitium
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "admin@reinitialized.net";
      dnsProvider = "technitium";
      credentialsFile = "${config.secrets.acmeDns.file}";
      dnsResolver = "10.255.0.3:53";
      extraLegoFlags = [ 
        "--pfx"
        "--pfx.pass="
        "--dns.resolvers=10.255.0.4:53"
        "--dns.propagation-wait=10s"
        "--dns-timeout=120"
      ];
    };
    certs."one.dns.reinitialized.net" = {
      postRun = ''
        # Copy PKCS#12 file from lego internal directory to output directory
        PFX_SRC=$(find /var/lib/acme/.lego/one.dns.reinitialized.net -name "*.pfx" -type f | head -1)
        if [[ -n "$PFX_SRC" ]]; then
          cp "$PFX_SRC" /var/lib/acme/one.dns.reinitialized.net/cert.pfx
          chmod 640 /var/lib/acme/one.dns.reinitialized.net/cert.pfx
          chown acme:acme /var/lib/acme/one.dns.reinitialized.net/cert.pfx
          echo "Copied PKCS#12 certificate to /var/lib/acme/one.dns.reinitialized.net/cert.pfx"
        else
          echo "Warning: No .pfx file found in lego directory"
        fi
      '';
      reloadServices = [
        "dnsOne"
      ];
    };
  };
  # Hosted Services
  ## Docker-based Containers
  virtualisation.oci-containers.containers = {
    ### Hudu
    hudu_postgres1 = {
      autoStart = true;
      hostname = "hudu_postgres1";
      image = "docker.io/library/postgres:18-alpine";
      environment = config.secrets.hudu.keys;
      networks = [ 
        "backend"
      ];
      ports = [
        "10.255.0.3:5432:5432/tcp"
      ];
      volumes = [
        "hudu_postgres1Data:/var/lib/postgresql/data"
      ];
    };
    hudu_redis1 = {
      autoStart = true;
      hostname = "hudu_redis1";
      image = "docker.io/library/redis:8-alpine";
      environment = config.secrets.hudu.keys;
      cmd = [ "redis-server" ];
      networks = [ 
        "backend"
      ];
      volumes = [
        "hudu_redis1Data:/var/lib/redis/data"
      ];
    };
    hudu1 = {
      autoStart = true;      
      hostname = "hudu1";
      image = "hududocker/hudu:latest";
      environment = config.secrets.hudu.keys;
      dependsOn = [
        "hudu_postgres1"
        "hudu_redis1"
      ];
      networks = [ 
        "backend"
      ];
      ports = [
        "10.255.0.3:3000:3000"
      ];
      volumes = [
        "hudu_data:/var/www/hudu2/public/uploads/"
        "hudu_data:/var/www/hudu2/uploads"
        "hudu_data:/var/lib/app/data"
      ];
    };
    hudu2 = {
      autoStart = true;
      hostname = "hudu2";
      image = "hududocker/hudu:latest";
      environment = config.secrets.hudu.keys;
      cmd = [ 
        "bundle" 
        "exec" 
        "sidekiq" 
        "-C" 
        "config/sidekiq.yml"
      ];
      dependsOn = [
        "hudu_postgres1"
        "hudu_redis1"
      ];
      networks = [ 
        "backend"
      ];
      volumes = [
        "hudu_data:/var/www/hudu2/public/uploads/"
        "hudu_data:/var/www/hudu2/uploads"
      ];
    };

    ### Technitium oneDns
    dnsOne = {
      autoStart = true;
      hostname = "dnsOne";
      image = "technitium/dns-server:14.3.0";
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.3:5380:5380"
        "10.255.0.3:53443:53443"
        "10.255.0.3:53:53/tcp"
        "10.255.0.3:53:53/udp"

        "10.1.11.2:53:53/tcp"
        "10.1.11.2:53:53/udp"
        "10.1.11.2:853:853/tcp"
        "10.1.11.2:853:853/udp"
        "10.1.11.2:67:67/udp"
      ];
      volumes = [
        "technitium_data:/etc/dns"
        "/var/lib/acme/one.dns.reinitialized.net:/etc/dns/certs:ro"
      ];
    };

    ### Stalwart Collaboration Server
    stalwartOne = {
      autoStart = true;
      hostname = "stalwart";
      image = "stalwartlabs/stalwart:latest";
      environment = {

      };
      networks = [
        "backend"
      ];
      ports = [
        # Web UI and ACME
        "10.255.0.3:8080:8080"

        # Mail protocols
        "10.255.0.3:25:25"
        "10.255.0.3:143:143"
        "10.255.0.3:465:465"
        "10.255.0.3:587:587"
        "10.255.0.3:993:993"
        "10.255.0.3:995:995"
        "10.255.0.3:4190:4190"
      ];
      volumes = [
        "stalwart_data:/opt/stalwart"
      ];
    };
  };
}