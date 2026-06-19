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
  services.containerAutoUpdate.skipContainers = [
    "immich-server"
    "immich-machine-learning"
    "tuwunel"
    "paperless-ngx"
    "pelican-panel"
    "ocis"
  ];

  # ownCloud OCIS Custom Content Security Policy
  environment.etc."ocis/csp.yaml".text = ''
    directives:
      default-src: ["'self'"]
      connect-src: ["'self'", "blob:", "https://access.reinitialized.net", "https://raw.githubusercontent.com"]
      script-src: ["'self'", "'unsafe-inline'"]
      style-src: ["'self'", "'unsafe-inline'"]
      img-src: ["'self'", "data:", "blob:"]
      frame-src: ["'self'"]
      frame-ancestors: ["'none'"]
  '';

  # ownCloud OCIS Proxy Configuration (Role Mapping)
  environment.etc."ocis/proxy.yaml".text = ''
    role_assignment:
      driver: oidc
      oidc_role_mapper:
        role_claim: groups
        role_mapping:
          - role_name: admin
            claim_value: OwnCloud - Administrators
          - role_name: admin
            claim_value: Super Administrators
          - role_name: user
            claim_value: OwnCloud - Users
          - role_name: user
            claim_value: Super User
          - role_name: user
            claim_value: Super Users
  '';

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

    ### ownCloud Infinite Scale (Cloud Storage)
    ocis = {
      autoStart = true;
      hostname = "ocis";
      image = "owncloud/ocis:latest";
      entrypoint = "/bin/sh";
      cmd = [ "-c" "ocis init || true; ocis server" ];
      environment = config.secrets.ocis.keys;
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.5:1028:9200/tcp"  # OCIS HTTP web UI + WebDAV
      ];
      volumes = [
        "ocis_config:/etc/ocis"
        "ocis_data:/var/lib/ocis"
        "/etc/ocis/csp.yaml:/etc/ocis/csp.yaml:ro"
        "/etc/ocis/proxy.yaml:/etc/ocis/proxy.yaml:ro"
      ];
    };

    ### SearXNG (Privacy-respecting Metasearch Engine)
    searxng = {
      autoStart = true;
      hostname = "searxng";
      image = "searxng/searxng:latest";
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.5:1029:8080/tcp"  # SearXNG web UI
      ];
      volumes = [
        "searxng_config:/etc/searxng"
      ];
    };
  };
}
