{
  config,
  ...
}:{
  # Networking Configuration
  networking = {
    hostName = "apps3";
    useDHCP = false;
  };
  systemd.network.networks = {
    "eth0" = {
      address = [
        "10.1.11.4/24"
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
  # Hosted Services
  ## Docker-based Containers
  virtualisation.oci-containers.containers = {
    ### PGAdmin4
    pgadmin4 = {
      autoStart = true;
      hostname = "pgadmin4";
      image = "dpage/pgadmin4:latest";
      environment = config.secrets.pgAdmin4.keys;
      networks = [
        "backend"
      ];
      ports = [  
        "10.255.0.5:80:80/tcp"     # pgAdmin4 web interface
      ];
      volumes = [
        "pgadmin4_data:/var/lib/pgadmin"
      ];
    };

    ### postgres1
    postgres1 = {
      autoStart = true;
      hostname = "postgres1";
      image = "docker.io/library/postgres:18-alpine";
      environment = config.secrets.postgres1.keys;
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.5:5432:5432/tcp"
      ];
      volumes = [
        "postgres1_data:/var/lib/postgresql/data"
      ];
    };

    ### redis1
    redis1 = {
      autoStart = true;
      hostname = "valkey1";
      image = "valkey/valkey:9-alpine";
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.5:6379:6379/tcp"
      ];
      volumes = [
        "valkey1_data:/data"
      ];
    };
  };
}