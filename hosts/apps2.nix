{
  config,
  pkgs,
  ...
}:{
  # Networking Configuration
  networking = {
    hostName = "apps2";
    useDHCP = false;
  };
  systemd.network.networks = {
    "eth0" = {
      address = [
        "10.1.11.3/24"
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
      nodeId = 4;
  };

  # ACME certificate generation for Technitium DNS (dnsTwo)
  # Generates certificate with PKCS#12 for direct use by Technitium
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "admin@reinitialized.net";
    };
    certs."two.dns.reinitialized.net" = {
      dnsProvider = "exec";
      credentialsFile = pkgs.writeText "lego-exec-env" ''
        EXEC_PATH=/etc/lego-dns-hook.sh
      '';
      dnsResolver = "10.255.0.3:53,10.255.0.4:53";
      extraLegoFlags = [ "--pfx" "--pfx.pass=" "--dns.propagation-wait=10s" "--dns-timeout=120" ];
      postRun = ''
        # Copy PKCS#12 file from lego internal directory to output directory
        PFX_SRC=$(find /var/lib/acme/.lego/two.dns.reinitialized.net -name "*.pfx" -type f | head -1)
        if [[ -n "$PFX_SRC" ]]; then
          cp "$PFX_SRC" /var/lib/acme/two.dns.reinitialized.net/cert.pfx
          chmod 640 /var/lib/acme/two.dns.reinitialized.net/cert.pfx
          chown acme:acme /var/lib/acme/two.dns.reinitialized.net/cert.pfx
          echo "Copied PKCS#12 certificate to /var/lib/acme/two.dns.reinitialized.net/cert.pfx"
        else
          echo "Warning: No .pfx file found in lego directory"
        fi
        # Restart dnsTwo container to reload certificate
        ${pkgs.docker}/bin/docker restart dnsTwo || true
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
    ### Technitium dnsTwo
    dnsTwo = {
      autoStart = true;
      hostname = "dnsTwo";
      image = "technitium/dns-server:14.3.0";
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.4:5380:5380"
        "10.255.0.4:53443:53443"
        "10.255.0.4:53:53/tcp"
        "10.255.0.4:53:53/udp"

        "10.1.11.3:53:53/tcp"
        "10.1.11.3:53:53/udp"
        "10.1.11.3:853:853/tcp"
        "10.1.11.3:853:853/udp"
        "10.1.11.3:67:67/udp"
      ];
      volumes = [
        "technitium_data:/etc/dns"
        "/var/lib/acme/two.dns.reinitialized.net:/etc/dns/certs:ro"
      ];
    };

    ### UniFi Network Controller - MongoDB
    unifi_mongodb = {
      autoStart = true;
      hostname = "unifi_mongodb";
      image = "docker.io/library/mongo:7.0";
      environment = {
        MONGO_INITDB_ROOT_USERNAME = config.secrets.unifi.keys.MONGO_USER;
        MONGO_INITDB_ROOT_PASSWORD = config.secrets.unifi.keys.MONGO_PASS;
      };
      networks = [
        "backend"
      ];
      volumes = [
        "unifi_mongodb_data:/data/db"
        "unifi_mongodb_config:/data/configdb"
      ];
    };

    ### UniFi Network Controller
    unifi = {
      autoStart = true;
      hostname = "unifi";
      image = "lscr.io/linuxserver/unifi-network-application:latest";
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/New_York";
        MONGO_USER = config.secrets.unifi.keys.MONGO_USER;
        MONGO_PASS = config.secrets.unifi.keys.MONGO_PASS;
        MONGO_HOST = config.virtualisation.oci-containers.containers.unifi_mongodb.hostname;
        MONGO_PORT = config.secrets.unifi.keys.MONGO_PORT;
        MONGO_DBNAME = config.secrets.unifi.keys.MONGO_DBNAME;
        MONGO_AUTHSOURCE = config.secrets.unifi.keys.MONGO_AUTHSOURCE;
      };
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.4:8443:8443/tcp"    # UniFi web admin
        "10.255.0.4:3478:3478/udp"     # STUN
        "10.255.0.4:10001:10001/udp"   # Device discovery
        "10.255.0.4:8080:8080/tcp"     # Device communication
      ];
      volumes = [
        "unifi_config:/config"
      ];
      dependsOn = [
        "unifi_mongodb"
      ];
    };
  };


}