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

  # Dedicated service account for certificate distribution from rp1
  # This account has minimal privileges - only write to cert dir and restart container
  users.users.certdist = {
    isSystemUser = true;
    group = "certdist";
    home = "/var/lib/certdist";
    createHome = true;
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keys = [
      config.secrets.certDistribution.keys.sshPublicKey
    ];
  };
  users.groups.certdist = {};

  # Certificate directory for certificates distributed from rp1
  # Certificates are pushed from rp1 via SSH/rsync over mesh network
  # Owned by certdist user so it can write certificates
  systemd.tmpfiles.rules = [
    "d /var/lib/acme/two.dns.reinitialized.net 0755 certdist certdist -"
  ];

  # Allow certdist to restart docker containers for cert reload
  # Using the symlink path which is stable across rebuilds
  security.sudo-rs.extraRules = [
    {
      users = [ "certdist" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/docker restart dnsTwo";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

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
        "10.255.0.4:53443:53443"

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