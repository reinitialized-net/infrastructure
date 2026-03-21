{
  config,
  ...
}: {
  # Networking Configuration
  networking = {
    hostName = "gs1";
    useDHCP = false;
    # Open game server port range for external clients (TCP + UDP)
    # Wings allocates ports from this range when creating game server containers.
    # Containers are created as Docker siblings on the host, so ports bind directly to the host.
    firewall.allowedTCPPortRanges = [
      { from = 25565; to = 25600; }
    ];
    firewall.allowedUDPPortRanges = [
      { from = 25565; to = 25600; }
    ];
    firewall.allowlist = [
      {
        # Wings SFTP for game file management (accessible within private LAN)
        port = 2022;
        protocol = "tcp";
        ipType = "ipv4";
        source = [
          "10.0.0.0/8"
          "172.16.0.0/12"
          "192.168.0.0/16"
        ];
      }
    ];
  };
  systemd.network.networks = {
    "eth0" = {
      address = [
        "10.1.11.6/24"
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

  # Ensure Pelican game data directories exist on the data disk
  systemd.tmpfiles.rules = [
    "d /mnt/data/pelican 0755 root root -"
    "d /tmp/pelican 0755 root root -"
  ];

  # Generate Wings config.yml on host from secrets (mounted read-only into container)
  environment.etc."pelican/config.yml" = {
    source = config.secrets.wings.file;
    mode = "0600";
  };

  # Hosted Services
  ## Docker-based Containers
  virtualisation.oci-containers.containers = {
    ### Pelican Wings (game server daemon)
    # Wings communicates with the Panel over the mesh network.
    # Game server containers are created as Docker siblings (via socket) and bind their
    # ports directly to the host — firewall rules above open the game port range.
    #
    # First-deploy note: Wings will restart until a valid config.yml is in place.
    # Workflow:
    #   1. Deploy this host and set up Pelican Panel on apps3
    #   2. In Panel: Nodes → New Node → copy the generated YAML
    #   3. Paste YAML content into modules/secrets/gs1.nix (secrets.wings.file)
    #   4. Run: rebuildHost gs1
    wings = {
      autoStart = true;
      hostname = "wings";
      image = "ghcr.io/pelican-dev/wings:latest";
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.6:1024:8080/tcp"  # Wings API (Panel → Wings, mesh only)
        "10.1.11.6:2022:2022/tcp"   # Wings SFTP (file management, VLAN accessible)
      ];
      volumes = [
        "/etc/pelican/config.yml:/etc/pelican/config.yml:ro"
        "wings_logs:/var/log/pelican"
        "/mnt/data/pelican:/var/lib/pelican"
        "/tmp/pelican:/tmp/pelican"
        "/var/run/docker.sock:/var/run/docker.sock"
      ];
      extraOptions = [
        "--group-add=999"  # Pass host Docker GID so Wings can access the socket
      ];
    };
  };
}
