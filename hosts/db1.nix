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

  # OpenTelemetry Collector Configuration
  environment.etc."otel-collector-config.yaml" = {
    text = ''
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: 0.0.0.0:4317
            http:
              endpoint: 0.0.0.0:4318

      processors:
        batch:
          timeout: 10s
          send_batch_size: 1024
        memory_limiter:
          check_interval: 1s
          limit_mib: 512

      exporters:
        # Export traces to Jaeger on apps1
        otlp/jaeger:
          endpoint: 10.255.0.3:1038
          tls:
            insecure: true
        # Export metrics to Prometheus
        prometheus:
          endpoint: "0.0.0.0:8889"
        logging:
          loglevel: info

      service:
        pipelines:
          traces:
            receivers: [otlp]
            processors: [memory_limiter, batch]
            exporters: [otlp/jaeger, logging]
          metrics:
            receivers: [otlp]
            processors: [memory_limiter, batch]
            exporters: [prometheus, logging]
          logs:
            receivers: [otlp]
            processors: [memory_limiter, batch]
            exporters: [logging]
    '';
    mode = "0644";
  };

  # Prometheus Configuration
  environment.etc."prometheus-config.yaml" = {
    text = ''
      global:
        scrape_interval: 15s
        evaluation_interval: 15s

      scrape_configs:
        # Scrape metrics from OTel Collector's Prometheus exporter
        - job_name: 'otel-collector'
          static_configs:
            - targets: ['otel-collector:8889']
        
        # Scrape Stalwart's Prometheus endpoint (if enabled)
        - job_name: 'stalwart'
          static_configs:
            - targets: ['10.255.0.3:1029']
    '';
    mode = "0644";
  };

  # Hosted Services
  ## Docker-based Containers
  virtualisation.oci-containers.containers = {
    ### OpenTelemetry Collector
    otel-collector = {
      autoStart = true;
      hostname = "otel-collector";
      image = "otel/opentelemetry-collector-contrib:latest";
      cmd = [ "--config=/etc/otel-collector-config.yaml" ];
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.11:1026:4317/tcp"  # OTLP gRPC
        "10.255.0.11:1027:4318/tcp"  # OTLP HTTP
        "10.255.0.11:1028:8889/tcp"  # Prometheus metrics endpoint
      ];
      volumes = [
        "/etc/otel-collector-config.yaml:/etc/otel-collector-config.yaml:ro"
      ];
    };

    ### Prometheus Time Series Database
    prometheus = {
      autoStart = true;
      hostname = "prometheus";
      image = "prom/prometheus:latest";
      cmd = [
        "--config.file=/etc/prometheus/prometheus.yml"
        "--storage.tsdb.path=/prometheus"
        "--web.console.libraries=/usr/share/prometheus/console_libraries"
        "--web.console.templates=/usr/share/prometheus/consoles"
      ];
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.11:1029:9090/tcp"  # Prometheus web UI and API
      ];
      volumes = [
        "prometheus_data:/prometheus"
        "/etc/prometheus-config.yaml:/etc/prometheus/prometheus.yml:ro"
      ];
    };

    ### postgres1
    postgres1 = {
      autoStart = true;
      hostname = "postgres1";
      # pgvector/pgvector:pg18 provides PostgreSQL 18 with the pgvector extension
      # Required for Immich on apps3. Same PG18 major version as before;
      # volume mount and PGDATA path are unchanged — no data migration needed.
      # Back up postgres1_data volume before first deploy with this image.
      image = "pgvector/pgvector:pg18";
      environment = config.secrets.postgres1.keys;
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.11:1024:5432/tcp"
      ];
      volumes = [
        # PostgreSQL 18+ requires mounting at /var/lib/postgresql (not /data subdirectory)
        # This is a breaking change from PostgreSQL 17 and below
        # See: https://hub.docker.com/_/postgres (PGDATA section)
        "postgres1_data:/var/lib/postgresql"
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