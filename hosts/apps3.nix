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

    ### Paperless-ngx (Document Management)
    paperless-ngx = {
      autoStart = true;
      hostname = "paperless-ngx";
      image = "ghcr.io/paperless-ngx/paperless-ngx:latest";
      environment = config.secrets.paperless.keys;
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.5:1026:8000/tcp"  # Paperless-ngx web UI and API
      ];
      volumes = [
        "paperless_data:/usr/src/paperless/data"
        "paperless_media:/usr/src/paperless/media"
        "paperless_export:/usr/src/paperless/export"
        "paperless_consume:/usr/src/paperless/consume"
      ];
    };

    ### Pelican Panel (Game Server Management)
    pelican-panel = {
      autoStart = true;
      hostname = "pelican-panel";
      image = "ghcr.io/pelican-dev/panel:latest";
      environment = config.secrets.pelican.keys;
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.5:1027:80/tcp"  # Pelican Panel web UI
      ];
      volumes = [
        "pelican_panel_var:/app/var"
        "pelican_panel_logs:/app/storage/logs"
      ];
    };

    ### RustDesk ID/Rendezvous Server (hbbs)
    # Coordinates peer connections; tells clients where the relay server is (-r flag)
    # NOTE: Port 21114 ("admin UI") does not exist in the OSS image - Pro only.
    rustdesk-hbbs = {
      autoStart = true;
      hostname = "rustdesk-hbbs";
      image = "rustdesk/rustdesk-server:latest";
      cmd = [ "hbbs" "-r" "ra.reinitialized.net:21117" ];
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.5:1028:21115/tcp"  # NAT type test
        "10.255.0.5:1029:21116/tcp"  # TCP hole-punch / ID registration
        "10.255.0.5:1029:21116/udp"  # UDP hole-punch / heartbeat
        "10.255.0.5:1030:21118/tcp"  # WebSocket for hbbs
      ];
      volumes = [
        "rustdesk_data:/root"  # Shared key pair with hbbr
      ];
    };

    ### RustDesk Relay Server (hbbr)
    # Relays encrypted traffic when direct P2P connection is not possible
    rustdesk-hbbr = {
      autoStart = true;
      hostname = "rustdesk-hbbr";
      image = "rustdesk/rustdesk-server:latest";
      cmd = [ "hbbr" ];
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.5:1031:21117/tcp"  # Relay
        "10.255.0.5:1032:21119/tcp"  # WebSocket relay
      ];
      volumes = [
        "rustdesk_data:/root"  # Shared key pair with hbbs
      ];
      dependsOn = [
        "rustdesk-hbbs"
      ];
    };
  };
}
