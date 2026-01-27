{
  config,
  pkgs,
  ...
}:{
  # Networking Configuration
  networking = {
    hostName = "apps2";
    useDHCP = false;
    # Restrict cluster ports to mesh network only
    firewall.allowlist = [
      {
        port = 5380;
        protocol = "tcp";
        ipType = "ipv4";
        source = [ "10.255.0.0/24" ];  # Mesh only - admin UI
      }
      {
        port = 53443;
        protocol = "tcp";
        ipType = "ipv4";
        source = [ "10.255.0.0/24" ];  # Mesh only - cluster sync
      }
    ];
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

  # Add rp1 cert distribution SSH key to rnetadmin authorized keys
  users.users.rnetadmin.openssh.authorizedKeys.keys = [
    config.secrets.certDistribution.keys.sshPublicKey
  ];

  # Certificate directory for certificates distributed from rp1
  # Certificates are pushed from rp1 via SSH/rsync over mesh network
  systemd.tmpfiles.rules = [
    "d /var/lib/acme/two.dns.reinitialized.net 0750 root root -"
  ];

  # Allow rnetadmin to restart docker containers for cert reload
  security.sudo-rs.extraRules = [
    {
      users = [ "rnetadmin" ];
      commands = [
        {
          command = "${pkgs.docker}/bin/docker restart dnsTwo";
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
        "10.255.0.4:5380:5380"
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