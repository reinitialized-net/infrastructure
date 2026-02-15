{
  config,
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
  };
  # ACME certificate generation for Technitium DNS (dnsOne)
  # Generates certificate with PKCS#12 for direct use by Technitium
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "admin@reinitialized.net";
      #server = "https://acme-staging-v02.api.letsencrypt.org/directory";
      profile = "shortlived";
      dnsProvider = "technitium";
      credentialsFile = config.secrets.acmeDns.file;
      dnsResolver = "10.255.0.3:1028";
      extraLegoFlags = [ 
        "--pfx"
        "--pfx.pass="
        "--dns.resolvers=10.255.0.4:1026"
        "--dns.propagation-wait=10s"
        "--dns-timeout=120"
      ];
    };
    certs."one.dns.reinitialized.net" = {
      postRun = ''
        # Copy PKCS#12 file from lego internal directory to output directory
        PFX_SRC=$(find /var/lib/acme/.lego/one.dns.reinitialized.net -name "*.pfx" -type f | head -1)
        if [[ -n "$PFX_SRC" ]]; then
          cp "$PFX_SRC" /var/lib/acme/one.dns.reinitialized.net/cert.pfx
          chmod 640 /var/lib/acme/one.dns.reinitialized.net/cert.pfx
          chown acme:acme /var/lib/acme/one.dns.reinitialized.net/cert.pfx
          echo "Copied PKCS#12 certificate to /var/lib/acme/one.dns.reinitialized.net/cert.pfx"
        else
          echo "Warning: No .pfx file found in lego directory"
        fi
      '';
      reloadServices = [
        "dnsOne"
      ];
    };
  };
  # Hosted Services
  ## Docker-based Containers
  virtualisation.oci-containers.containers = {
    ### Hudu
    hudu1 = {
      autoStart = true;      
      hostname = "hudu1";
      image = "hududocker/hudu:latest";
      environment = config.secrets.hudu.keys;
      networks = [ 
        "backend"
      ];
      ports = [
        "10.255.0.3:1025:3000"
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
        "10.255.0.3:1026:5380"
        "10.255.0.3:1027:53443"
        "10.255.0.3:1028:53/tcp"
        "10.255.0.3:1028:53/udp"

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

    ### Stalwart Collaboration Server
    stalwartOne = {
      autoStart = true;
      hostname = "stalwart";
      image = "stalwartlabs/stalwart:latest";
      networks = [
        "backend"
      ];
      ports = [
        # Web UI HTTP (ACME HTTP-01 challenges, API, metrics)
        "10.255.0.3:1029:8080"

        # Web UI HTTPS (TLS terminated by Stalwart via native ACME)
        "10.255.0.3:1042:443"

        # Prometheus metrics endpoint (if enabled in config.toml)
        "10.255.0.3:1041:9090"

        # Mail protocols (TLS handled by Stalwart for implicit-TLS ports)
        "10.255.0.3:1030:25"
        "10.255.0.3:1031:143"
        "10.255.0.3:1032:465"
        "10.255.0.3:1033:587"
        "10.255.0.3:1034:993"
        "10.255.0.3:1035:995"
        "10.255.0.3:1036:4190"
      ];
      volumes = [
        "stalwart_data:/opt/stalwart"
      ];
    };

    ### Forgejo Git Forge
    forgejo = {
      autoStart = true;
      hostname = "forgejo";
      image = "code.forgejo.org/forgejo/forgejo:14";
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.3:1037:3000"
      ];
      volumes = [
        "forgejo_data:/data"
        "/etc/timezone:/etc/timezone:ro"
        "/etc/localtime:/etc/localtime:ro"
      ];
    };

    ### Jaeger UI (Tracing Visualization)
    jaeger = {
      autoStart = true;
      hostname = "jaeger";
      image = "jaegertracing/all-in-one:latest";
      environment = config.secrets.jaeger.keys;
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.3:1038:4317/tcp"   # OTLP gRPC receiver (from OTel Collector)
        "10.255.0.3:1039:16686/tcp"  # Jaeger UI
      ];
      volumes = [
        "jaeger_data:/badger"
      ];
    };

    ### Grafana (Metrics Visualization)
    grafana = {
      autoStart = true;
      hostname = "grafana";
      image = "grafana/grafana:latest";
      environment = config.secrets.grafana.keys;
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.3:1040:3000/tcp"  # Grafana web UI
      ];
      volumes = [
        "grafana_data:/var/lib/grafana"
      ];
    };
  };
}