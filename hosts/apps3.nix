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
    ### Immich Server (API + Web UI + Microservices)
    immich-server = {
      autoStart = true;
      hostname = "immich-server";
      image = "ghcr.io/immich-app/immich-server:release";
      environment = config.secrets.immich.keys;
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.5:1001:2283/tcp"  # Immich web UI and API
      ];
      volumes = [
        "immich_upload:/usr/src/app/upload"
        "/etc/localtime:/etc/localtime:ro"
      ];
      dependsOn = [
        "immich-machine-learning"
      ];
    };

    ### Immich Machine Learning (inference engine)
    immich-machine-learning = {
      autoStart = true;
      hostname = "immich-machine-learning";
      image = "ghcr.io/immich-app/immich-machine-learning:release";
      networks = [
        "backend"
      ];
      volumes = [
        "immich_ml_cache:/cache"
      ];
    };

    ### Tuwunel Matrix Homeserver (successor to Conduwuit)
    tuwunel = {
      autoStart = true;
      hostname = "tuwunel";
      image = "ghcr.io/matrix-construct/tuwunel:v1.5.0";
      environment = config.secrets.tuwunel.keys;
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.5:1025:8008/tcp"  # Matrix client/server API
      ];
      volumes = [
        "tuwunel_data:/var/lib/tuwunel"
      ];
    };
  };
}
