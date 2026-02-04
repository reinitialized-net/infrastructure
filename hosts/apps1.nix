{
  config,
  pkgs,
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
      nodeId = 3;
  };

  # ACME certificate generation for Technitium DNS (dnsOne)
  # Generates certificate with PKCS#12 for direct use by Technitium
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "admin@reinitialized.net";
    };
    certs."one.dns.reinitialized.net" = {
      # Use webroot validation since Technitium can serve HTTP challenges
      # or use DNS validation if configured
      dnsProvider = "exec";
      credentialsFile = pkgs.writeText "lego-exec-env" ''
        EXEC_PATH=/etc/lego-dns-hook.sh
      '';
      dnsResolver = "10.255.0.3:53,10.255.0.4:53";
      extraLegoFlags = [ "--pfx" "--pfx.pass=" "--dns.propagation-wait=10s" "--dns-timeout=120" ];
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
        # Restart dnsOne container to reload certificate
        ${pkgs.docker}/bin/docker restart dnsOne || true
      '';
    };
  };
  
  # Custom DNS script for ACME that updates primary and triggers secondary resync
  environment.etc."lego-dns-hook.sh" = {
    mode = "0755";
    text = ''
      #!/bin/sh
      # LEGO_DNS_HOOK for Technitium DNS with cluster sync
      # Called with: present/cleanup <domain> <token> <keyauth>
      
      ACTION="$1"
      DOMAIN="$2"
      TOKEN="$3"
      
      PRIMARY_URL="http://10.255.0.3:5380"
      SECONDARY_URL="http://10.255.0.4:5380"
      API_TOKEN="${config.secrets.acmeDns.keys.apiToken}"
      
      # Extract zone from domain (remove _acme-challenge. prefix)
      ZONE=$(echo "$DOMAIN" | sed 's/^_acme-challenge\.//')
      
      case "$ACTION" in
        present)
          # Add TXT record to primary
          ${pkgs.curl}/bin/curl -s "$PRIMARY_URL/api/zones/records/add?token=$API_TOKEN&domain=$DOMAIN&zone=$ZONE&type=TXT&text=$TOKEN" >/dev/null
          
          # Trigger zone resync on secondary
          sleep 1
          ${pkgs.curl}/bin/curl -s "$SECONDARY_URL/api/zones/resync?token=$API_TOKEN&domain=$ZONE" >/dev/null
          
          # Wait for resync to complete
          sleep 3
          ;;
        cleanup)
          # Delete TXT record from primary
          ${pkgs.curl}/bin/curl -s "$PRIMARY_URL/api/zones/records/delete?token=$API_TOKEN&domain=$DOMAIN&zone=$ZONE&type=TXT&text=$TOKEN" >/dev/null
          
          # Trigger zone resync on secondary
          ${pkgs.curl}/bin/curl -s "$SECONDARY_URL/api/zones/resync?token=$API_TOKEN&domain=$ZONE" >/dev/null
          ;;
      esac
    '';
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
  };
}