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
    "d /var/lib/acme/one.dns.reinitialized.net 0755 certdist certdist -"
  ];

  # Allow certdist to restart docker containers for cert reload
  # Using the symlink path which is stable across rebuilds
  security.sudo-rs.extraRules = [
    {
      users = [ "certdist" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/docker restart dnsOne";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
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
        "10.255.0.3:53443:53443"

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