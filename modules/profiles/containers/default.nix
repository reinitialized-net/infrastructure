{
  self,
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.services.containerAutoUpdate;
  containerEntries = lib.mapAttrsToList
    (name: container: {
      name = name;
      image = container.image;
      serviceName = if container ? serviceName then container.serviceName else "docker-${name}";
    })
    config.virtualisation.oci-containers.containers;

  containerDefinitionsScript = lib.concatMapStringsSep "\n" (entry:
    "${entry.name}|${entry.image}|${entry.serviceName}"
  ) containerEntries;

  skipContainersScript = lib.concatMapStringsSep "\n" (entry: entry) cfg.skipContainers;

  # Validation script for docker user SSH commands.
  # Only allows commands needed for volume migration:
  #   - docker: run, stop, start, ps, volume create/inspect (transfer operations)
  #   - scp/sftp-server: file transfers (modern scp uses SFTP protocol internally)
  # This is used as a ForceCommand in sshd_config to restrict the docker user's SSH access.
  dockerSshValidator = pkgs.writeScript "docker-ssh-validator" ''
    #!/bin/sh
    cmd="$SSH_ORIGINAL_COMMAND"
    case "$cmd" in
      */bin/docker*|docker*|scp*|*/sftp-server*|sftp-server*)
        eval "$cmd"
        ;;
      *)
        echo "Access denied: only volume migration commands are permitted" >&2
        exit 1
        ;;
    esac
  '';
  in {
  imports = [ 
    "${self}/modules/profiles/meshNetwork"
    "${self}/modules/profiles/secrets.nix"
    ./containerTools.nix
  ];

  options.services.containerAutoUpdate = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether OCI container image auto-updates are enabled.";
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "04:00";
      description = ''
        Systemd OnCalendar expression for the automatic container image update check.
        Use standard systemd calendar syntax.
      '';
      example = "Mon *-*-* 03:30:00";
    };

    randomizedDelaySec = lib.mkOption {
      type = lib.types.str;
      default = "15min";
      description = "Optional randomized delay added to timer activation.";
    };

    skipContainers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Container names from `virtualisation.oci-containers.containers` to skip during
        image pull/restart checks.
      '';
      example = [ "stateful-db" "wireguard" ];
    };

    pullOnly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Only pull images; do not restart any containers.";
    };

    restartChangedOnly = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        When true, containers are restarted only if the pulled image digest changes.
        If false, containers are restarted after every successful pull.
      '';
    };
  };

  config = {
    virtualisation = {
      docker = {
        enable = lib.mkForce true;
        daemon.settings = {
          icc = lib.mkForce true;
          no-new-privileges = lib.mkForce true;
        };
        # Ensure containers inherit host time and timezone
        extraOptions = "--default-ulimit nofile=65536:65536";
      };
      oci-containers.backend = lib.mkForce "docker";
    };

    boot.kernelParams = lib.mkIf (!config.boot.isContainer) [ "systemd.unified_cgroup_hierarchy=1" ];

    # Automatically prune stopped containers, dangling images, and unused networks daily.
    # This prevents stale CI job containers (e.g. from Forgejo Runner) from accumulating
    # and filling the data disk.
    virtualisation.docker.autoPrune = {
      enable = true;
      dates = "daily";
      flags = [ "--filter" "until=24h" ];
    };

    # Declarative OCI container image maintenance.
    systemd.services.docker-container-auto-update = lib.mkIf cfg.enable {
      description = "Update Docker OCI container images from declarative definitions";
      after = [ "docker.service" ];
      serviceConfig = {
        Type = "oneshot";
      };
      path = [ pkgs.bash pkgs.coreutils pkgs.docker pkgs.systemd ];
      script = ''
        #!/usr/bin/env bash
        set -euo pipefail

        pull_only=${if cfg.pullOnly then "true" else "false"}
        restart_changed_only=${if cfg.restartChangedOnly then "true" else "false"}

        skip_containers="${skipContainersScript}"

        container_entries="${containerDefinitionsScript}"

        is_skipped() {
          local target="$1"
          while IFS= read -r candidate; do
            [ -z "$candidate" ] && continue
            if [ "$candidate" = "$target" ]; then
              return 0
            fi
          done <<< "$skip_containers"
          return 1
        }

        get_image_id() {
          local image="$1"
          docker image inspect --format '{{.Id}}' "$image" 2>/dev/null || echo "__IMAGE_UNKNOWN__"
        }

        if [ -z "$container_entries" ]; then
          echo "No OCI containers are configured under virtualisation.oci-containers.containers."
          exit 0
        fi

        while IFS= read -r entry; do
          [ -z "$entry" ] && continue
          IFS='|' read -r container_name container_image container_service <<< "$entry"

          if is_skipped "$container_name"; then
            echo "Skipping container: $container_name"
            continue
          fi

          before_id="$(get_image_id "$container_image")"
          if ! docker pull "$container_image"; then
            echo "Failed to pull image for $container_name ($container_image)"
            continue
          fi

          if [[ "$pull_only" == "true" ]]; then
            echo "Pulled image for $container_name; pull-only mode enabled."
            continue
          fi

          after_id="$(get_image_id "$container_image")"
          unit_name="$(printf '%s' "$container_service" | sed 's/\\.service$//').service"

          if ! systemctl cat "$unit_name" > /dev/null 2>&1; then
            echo "Container service $unit_name not found; skipping."
            continue
          fi

          if [[ "$restart_changed_only" == "true" && "$before_id" == "$after_id" ]]; then
            echo "No image change for $container_name; skipping restart."
            continue
          fi

          echo "Restarting $container_name service ($unit_name)"
          if ! systemctl restart "$unit_name"; then
            echo "Failed to restart $unit_name"
            exit 1
          fi
        done <<< "$container_entries"
      '';
    };

    systemd.timers.docker-container-auto-update = lib.mkIf cfg.enable {
      description = "Run Docker container image update checks";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        RandomizedDelaySec = cfg.randomizedDelaySec;
        Persistent = true;
      };
    };

    fileSystems = {
      "/var/lib/docker/volumes" = {
        depends = [ "/mnt/data" ];
        device = "/mnt/data/docker/volumes";
        fsType = "none";
        options = [ "bind" ];
      };
      "/var/lib/docker" = lib.mkForce {
        device = "/mnt/data/docker";
        depends = [ "/mnt/data/docker/volumes" ];
        fsType = "none";
        options = [ "bind" ];
      };
    };

    users = {
      groups.docker = lib.mkForce {};

      users.docker = {
        isSystemUser = lib.mkForce true;
        shell = lib.mkForce pkgs.bashInteractive;
        home = lib.mkForce "/home/docker";
        createHome = lib.mkForce true;
        group = lib.mkForce "docker";
        initialHashedPassword = lib.mkForce "!";

        # SSH authorized key for volume migration between Docker hosts
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFfLHdV15r9vsPKZsrzLMjOfH9VgsKF8SK2vu9A6kDsJ docker-volume-migration"
        ];
      };
    };

    # Allow docker group members to run ssh as the docker user for volume migration.
    # This is scoped to only the ssh binary — no general shell access.
    security.sudo-rs.extraRules = [
      {
        groups = [ "docker" ];
        commands = [
          { command = "${pkgs.openssh}/bin/ssh *"; options = [ "NOPASSWD" "SETENV" ]; }
          { command = "${pkgs.coreutils}/bin/test *"; options = [ "NOPASSWD" ]; }
        ];
        runAs = "docker";
      }
    ];

    # Restrict the docker user's SSH access to only SCP/SFTP file transfers
    # and docker commands needed for volume migration. No interactive shell,
    # no port forwarding, no agent forwarding.
    services.openssh.extraConfig = ''
      Match User docker
        AllowTcpForwarding no
        AllowAgentForwarding no
        X11Forwarding no
        PermitTunnel no
        ForceCommand ${dockerSshValidator}
    '';

    # Deploy the SSH private key for the docker user to use when connecting to other hosts.
    # The key is sourced from config.secrets.volumeMigration.file and written with
    # strict permissions (0600, owned by docker:docker) as required by SSH.
    systemd.services.deploy-docker-migration-key = {
      description = "Deploy SSH private key for docker volume migration";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /home/docker/.ssh
        # Write key, stripping leading whitespace from heredoc-style nix strings
        sed 's/^[[:space:]]*//' "${config.secrets.volumeMigration.file}" > /home/docker/.ssh/volume-migration-key
        chmod 700 /home/docker/.ssh
        chmod 600 /home/docker/.ssh/volume-migration-key
        chown -R docker:docker /home/docker/.ssh

        # Configure SSH client for the docker user to use this key and
        # accept new host keys automatically (mesh IPs are trusted)
        cat > /home/docker/.ssh/config << 'EOF'
        Host *
          IdentityFile /home/docker/.ssh/volume-migration-key
          StrictHostKeyChecking accept-new
          UserKnownHostsFile /home/docker/.ssh/known_hosts
        EOF
        chmod 600 /home/docker/.ssh/config
        chown docker:docker /home/docker/.ssh/config
      '';
    };
  };
}
