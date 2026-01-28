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
      ];
      volumes = [
        "technitium_data:/etc/dns"
        "/var/lib/acme/two.dns.reinitialized.net:/etc/dns/certs:ro"
      ];
    };
  };
}