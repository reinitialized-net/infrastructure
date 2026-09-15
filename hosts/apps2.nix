{
  config,
  lib,
  pkgs,
  ...
}:
{
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
  };
  services.containerAutoUpdate.skipContainers = [
    "dnsTwo"
    "unifi_mongodb"
    "unifi"
    "forgejoRunner"
  ];
  # ACME certificate generation for Technitium DNS (dnsTwo)
  # Generates certificate with PKCS#12 for direct use by Technitium
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "admin@reinitialized.net";
      #server = "https://acme-staging-v02.api.letsencrypt.org/directory";
      profile = "shortlived";
      dnsProvider = "technitium";
      environmentFile = config.secrets.acmeDns.file;
      dnsResolver = "10.255.0.3:1028";
      extraLegoFlags = [
        "--dns.resolvers=10.255.0.4:1026"
        "--dns.propagation-wait=10s"
        "--dns-timeout=120"
      ];
    };
    certs."two.dns.reinitialized.net" = {
      postRun = ''
        # Publish the installed certificate atomically; lego's internal layout can change.
        (
          set -euo pipefail
          umask 077
          cert_dir=/var/lib/acme/two.dns.reinitialized.net
          pfx_tmp=$(mktemp "$cert_dir/.cert.pfx.XXXXXX")
          trap 'rm -f "$pfx_tmp"' EXIT
          ${pkgs.openssl}/bin/openssl pkcs12 -export \
            -inkey "$cert_dir/key.pem" -in "$cert_dir/fullchain.pem" \
            -out "$pfx_tmp" -passout pass:
          chmod 640 "$pfx_tmp"
          chown acme:acme "$pfx_tmp"
          mv -f "$pfx_tmp" "$cert_dir/cert.pfx"
        )
      '';
      reloadServices = [
        "docker-dnsTwo.service"
      ];
    };
  };
  # Hosted Services
  ## Docker-based Containers
  virtualisation.oci-containers.containers = {
    ### Technitium dnsTwo
    dnsTwo = {
      autoStart = true;
      hostname = "dnsTwo";
      image = "technitium/dns-server:15.4.0";
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.4:1024:5380"
        "10.255.0.4:1025:53443"
        "10.255.0.4:1026:53/tcp"
        "10.255.0.4:1026:53/udp"

        "10.1.11.3:53:53/tcp"
        "10.1.11.3:53:53/udp"
        "10.1.11.3:853:853/tcp"
        "10.1.11.3:853:853/udp"
        "10.1.11.3:67:67/udp"
      ];
      volumes = [
        "technitium_data:/etc/dns"
        "/var/lib/acme/two.dns.reinitialized.net:/etc/dns/certs:ro"
      ];
    };

    ## UniFi Network Controller
    unifi_mongodb = {
      autoStart = true;
      hostname = "unifi_mongodb";
      image = "docker.io/library/mongo:7.0";
      environmentFiles = [ "/var/lib/service-secrets/unifi-mongodb.env" ];
      networks = [
        "backend"
      ];
      volumes = [
        "unifi_mongodb_data:/data/db"
        "unifi_mongodb_config:/data/configdb"
      ];
    };
    unifi = {
      autoStart = true;
      hostname = "unifi";
      image = "lscr.io/linuxserver/unifi-network-application:latest";
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/New_York";
        MONGO_HOST = config.virtualisation.oci-containers.containers.unifi_mongodb.hostname;
      };
      environmentFiles = [ "/var/lib/service-secrets/unifi.env" ];
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.4:1027:8443/tcp" # UniFi web admin
        "10.255.0.4:1028:3478/udp" # STUN
        "10.255.0.4:1029:10001/udp" # Device discovery
        "10.255.0.4:1030:8080/tcp" # Device communication
      ];
      volumes = [
        "unifi_config:/config"
      ];
      dependsOn = [
        "unifi_mongodb"
      ];
    };

    ### PGAdmin4
    pgadmin4 = {
      autoStart = true;
      hostname = "pgadmin4";
      image = "dpage/pgadmin4:latest";
      environment = builtins.removeAttrs config.secrets.pgAdmin4.keys [ "PGADMIN_DEFAULT_PASSWORD" ];
      environmentFiles = [ "/var/lib/service-secrets/pgadmin4.env" ];
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.4:1031:8080/tcp" # pgAdmin4 web interface
      ];
      volumes = [
        "pgadmin4_data:/var/lib/pgadmin"
      ];
    };

    ### Redis Insight
    redisInsight = {
      autoStart = true;
      hostname = "redisInsight";
      image = "redis/redisinsight:latest";
      environment = builtins.removeAttrs config.secrets.redisInsight.keys [
        "RI_REDIS_USERNAME1"
        "RI_REDIS_PASSWORD1"
      ];
      environmentFiles = [ "/var/lib/service-secrets/redisinsight.env" ];
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.4:1032:5540" # Redis Insight web interface
      ];
      volumes = [
        "redisInsight_data:/data"
      ];
    };

    ### Forgejo Runner (CI/CD)
    forgejoRunner = {
      autoStart = true;
      hostname = "forgejoRunner";
      image = "code.forgejo.org/forgejo/runner:13";
      environment = builtins.removeAttrs config.secrets.forgejoRunner.keys [
        "FORGEJO_RUNNER_REGISTRATION_TOKEN"
        "FORGEJO_ADMIN_API_TOKEN"
      ];
      environmentFiles = [ "/var/lib/service-secrets/forgejo-runner.env" ];
      cmd = [
        "bash"
        "-c"
        ''
          # Read the registration credential at runtime; the env file keeps it out of the store.
          CONFIGURED_LABELS="$FORGEJO_RUNNER_LABELS"

          # Generate config.yml if it doesn't exist
          if [ ! -f /data/config.yml ]; then
            forgejo-runner generate-config > /data/config.yml
            echo "Generated default config.yml"

            # Patch config.yml with desired settings
            sed -i "s|^  capacity: 1|  capacity: $FORGEJO_RUNNER_CAPACITY|" /data/config.yml
            sed -i "s|^  fetch_timeout: 5s|  fetch_timeout: $FORGEJO_RUNNER_FETCH_TIMEOUT|" /data/config.yml
            sed -i "s|^  fetch_interval: 2s|  fetch_interval: $FORGEJO_RUNNER_FETCH_INTERVAL|" /data/config.yml

            # Configure Docker socket access - automount will automatically find and mount the socket
            sed -i 's|^  docker_host: "-"|  docker_host: "automount"|' /data/config.yml
          fi

          # Register the runner against the Forgejo instance
          register_runner() {
            echo "Registering runner..."
            forgejo-runner register \
              --no-interactive \
              --instance "$FORGEJO_INSTANCE_URL" \
              --token "$FORGEJO_RUNNER_REGISTRATION_TOKEN" \
              --name "$FORGEJO_RUNNER_NAME" \
              --labels "$CONFIGURED_LABELS" \
              --config /data/config.yml
            return $?
          }

          # Never give the job runner a Forgejo admin token. Label changes are
          # rare and must be deregistered by an administrator before local state
          # is removed.
          STORED_LABELS=$(cat /data/.runner-labels 2>/dev/null || echo "")
          if [ -f /data/.runner ] && [ "$CONFIGURED_LABELS" != "$STORED_LABELS" ]; then
            echo "Runner labels changed; deregister it in Forgejo before removing /data/.runner." >&2
            echo "  Was: $STORED_LABELS"
            echo "  Now: $CONFIGURED_LABELS"
            exit 1
          fi

          # Register if not already registered
          if [ ! -f /data/.runner ]; then
            if register_runner; then
              echo "Runner registered successfully"
              echo "$CONFIGURED_LABELS" > /data/.runner-labels
            else
              echo "Registration failed. Exiting."
              exit 1
            fi
          fi

          exec forgejo-runner daemon --config /data/config.yml
        ''
      ];
      networks = [
        "backend"
      ];
      volumes = [
        "forgejoRunner_data:/data"
        "/var/run/docker.sock:/var/run/docker.sock"
      ];
      workdir = "/data";
      extraOptions = [
        # Add docker group (GID 999) for socket access
        # Must use numeric GID since the container doesn't have 'docker' in /etc/group
        "--group-add=999"
      ];
    };

    ### Cinny Matrix Web Client
    cinny = {
      autoStart = true;
      hostname = "cinny";
      image = "ghcr.io/cinnyapp/cinny:v4.12.6";
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.4:1040:80/tcp" # Cinny web UI
      ];
      volumes = [
        "${
          pkgs.writeText "cinny-config" (
            builtins.toJSON {
              defaultHomeserver = 0;
              homeserverList = [ "reinitialized.me" ];
              allowCustomHomeservers = 1;
            }
          )
        }:/usr/share/nginx/html/config.json:ro"
      ];
    };
  };
}
