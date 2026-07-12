{
  config,
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
        "--pfx"
        "--pfx.pass="
        "--dns.resolvers=10.255.0.4:1026"
        "--dns.propagation-wait=10s"
        "--dns-timeout=120"
      ];
    };
    certs."two.dns.reinitialized.net" = {
      postRun = ''
        # Copy PKCS#12 file from lego internal directory to output directory
        PFX_SRC=$(find /var/lib/acme/.lego/two.dns.reinitialized.net -name "*.pfx" -type f | head -1)
        if [[ -n "$PFX_SRC" ]]; then
          cp "$PFX_SRC" /var/lib/acme/two.dns.reinitialized.net/cert.pfx
          chmod 640 /var/lib/acme/two.dns.reinitialized.net/cert.pfx
          chown acme:acme /var/lib/acme/two.dns.reinitialized.net/cert.pfx
          echo "Copied PKCS#12 certificate to /var/lib/acme/two.dns.reinitialized.net/cert.pfx"
        else
          echo "Warning: No .pfx file found in lego directory"
        fi
      '';
      reloadServices = [
        "dnsTwo"
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
      environment = {
        MONGO_INITDB_ROOT_USERNAME = config.secrets.unifi.keys.MONGO_USER;
        MONGO_INITDB_ROOT_PASSWORD = config.secrets.unifi.keys.MONGO_PASS;
      };
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
        MONGO_USER = config.secrets.unifi.keys.MONGO_USER;
        MONGO_PASS = config.secrets.unifi.keys.MONGO_PASS;
        MONGO_HOST = config.virtualisation.oci-containers.containers.unifi_mongodb.hostname;
        MONGO_PORT = config.secrets.unifi.keys.MONGO_PORT;
        MONGO_DBNAME = config.secrets.unifi.keys.MONGO_DBNAME;
        MONGO_AUTHSOURCE = config.secrets.unifi.keys.MONGO_AUTHSOURCE;
      };
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
      environment = config.secrets.pgAdmin4.keys;
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.4:1031:80/tcp" # pgAdmin4 web interface
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
      environment = config.secrets.redisInsight.keys;
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
      image = "code.forgejo.org/forgejo/runner:12";
      cmd = [
        "bash"
        "-c"
        ''
          # Secrets interpolated at Nix build time into bash variables
          FORGEJO_INSTANCE_URL="${config.secrets.forgejoRunner.keys.FORGEJO_INSTANCE_URL}"
          FORGEJO_ADMIN_TOKEN="${config.secrets.forgejoRunner.keys.FORGEJO_ADMIN_API_TOKEN}"
          CONFIGURED_LABELS="${config.secrets.forgejoRunner.keys.FORGEJO_RUNNER_LABELS}"

          # Generate config.yml if it doesn't exist
          if [ ! -f /data/config.yml ]; then
            forgejo-runner generate-config > /data/config.yml
            echo "Generated default config.yml"

            # Patch config.yml with desired settings
            sed -i 's|^  capacity: 1|  capacity: ${config.secrets.forgejoRunner.keys.FORGEJO_RUNNER_CAPACITY}|' /data/config.yml
            sed -i 's|^  fetch_timeout: 5s|  fetch_timeout: ${config.secrets.forgejoRunner.keys.FORGEJO_RUNNER_FETCH_TIMEOUT}|' /data/config.yml
            sed -i 's|^  fetch_interval: 2s|  fetch_interval: ${config.secrets.forgejoRunner.keys.FORGEJO_RUNNER_FETCH_INTERVAL}|' /data/config.yml

            # Configure Docker socket access - automount will automatically find and mount the socket
            sed -i 's|^  docker_host: "-"|  docker_host: "automount"|' /data/config.yml
          fi

          # Deregister the old runner from the Forgejo server before re-registering.
          # This prevents duplicate runner entries when re-registration is needed (e.g. label changes
          # or stale credentials). Reads the runner ID from .runner, calls the Forgejo admin API to
          # delete it, then removes the local state files.
          deregister_runner() {
            if [ ! -f /data/.runner ]; then
              return 0
            fi

            RUNNER_ID=$(grep -o '"id":[0-9]*' /data/.runner | head -1 | sed 's/"id"://')

            if [ -z "$RUNNER_ID" ]; then
              echo "Warning: Could not extract runner ID from .runner; skipping server-side deregistration"
            elif [ -z "$FORGEJO_ADMIN_TOKEN" ] || [ "$FORGEJO_ADMIN_TOKEN" = "REPLACE_WITH_FORGEJO_ADMIN_API_TOKEN" ]; then
              echo "Warning: FORGEJO_ADMIN_API_TOKEN not configured; skipping server-side deregistration (old runner entry may remain)"
            elif command -v curl > /dev/null 2>&1; then
              echo "Deregistering runner ID $RUNNER_ID from Forgejo..."
              HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
                -H "Authorization: token $FORGEJO_ADMIN_TOKEN" \
                "$FORGEJO_INSTANCE_URL/api/v1/admin/runners/$RUNNER_ID")
              echo "Forgejo deregister response: HTTP $HTTP_STATUS"
            else
              echo "Warning: curl not available; skipping server-side deregistration"
            fi

            rm -f /data/.runner /data/.runner-labels
          }

          # Register the runner against the Forgejo instance
          register_runner() {
            echo "Registering runner..."
            forgejo-runner register \
              --no-interactive \
              --instance "$FORGEJO_INSTANCE_URL" \
              --token "${config.secrets.forgejoRunner.keys.FORGEJO_RUNNER_REGISTRATION_TOKEN}" \
              --name "${config.secrets.forgejoRunner.keys.FORGEJO_RUNNER_NAME}" \
              --labels "$CONFIGURED_LABELS" \
              --config /data/config.yml
            return $?
          }

          # Detect label changes: if configured labels differ from what was used at last registration,
          # deregister the old runner first to avoid creating a duplicate entry in Forgejo.
          STORED_LABELS=$(cat /data/.runner-labels 2>/dev/null || echo "")
          if [ -f /data/.runner ] && [ "$CONFIGURED_LABELS" != "$STORED_LABELS" ]; then
            echo "Runner labels have changed — deregistering old runner to prevent duplicates..."
            echo "  Was: $STORED_LABELS"
            echo "  Now: $CONFIGURED_LABELS"
            deregister_runner
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

          # Start the runner daemon.
          # If it exits with failure (e.g. stale credentials after DB loss), deregister cleanly
          # and attempt one re-registration before giving up.
          if ! forgejo-runner daemon --config /data/config.yml; then
            echo "Runner daemon exited with failure. Attempting clean re-registration..."
            deregister_runner

            if register_runner; then
              echo "$CONFIGURED_LABELS" > /data/.runner-labels
              echo "Re-registration successful. Starting daemon again..."
              exec forgejo-runner daemon --config /data/config.yml
            else
              echo "Re-registration failed. Exiting."
              exit 1
            fi
          fi
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
        "--privileged"
        # Add docker group (GID 999) for socket access
        # Must use numeric GID since the container doesn't have 'docker' in /etc/group
        "--group-add=999"
      ];
    };

    ### Cinny Matrix Web Client
    cinny = {
      autoStart = true;
      hostname = "cinny";
      image = "ghcr.io/cinnyapp/cinny:v4.12.3";
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
