{
  config,
  ...
}:{
  # Networking Configuration
  networking = {
    hostName = "db1";
    useDHCP = false;
  };
  systemd.network.networks = {
    "eth0" = {
      address = [
        "10.1.11.11/24"
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
        "10.255.0.11:1024:5432/tcp"
      ];
      volumes = [
        "postgres1_data:/var/lib/postgresql/data"
      ];
    };

    ### valkey1
    valkey1 = {
      autoStart = true;
      hostname = "valkey1";
      image = "valkey/valkey:9-alpine";
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.11:1025:6379/tcp"
      ];
      volumes = [
        "valkey1_data:/data"
      ];
    };
  };
}