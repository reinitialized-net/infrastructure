{
  self,
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.containerAutoUpdate;
  containerEntries = lib.mapAttrsToList (name: container: {
    name = name;
    image = container.image;
    networks = container.networks;
    serviceName = if container ? serviceName then container.serviceName else "docker-${name}";
  }) config.virtualisation.oci-containers.containers;

  containerDefinitionsScript = lib.concatMapStringsSep "\n" (
    entry: "${entry.name}|${entry.image}|${entry.serviceName}"
  ) containerEntries;

  skipContainersScript = lib.concatMapStringsSep "\n" (entry: entry) cfg.skipContainers;

  containerFailureServices = lib.listToAttrs (
    map (
      entry:
      let
        usesMeshNetwork =
          config.services.meshNetwork.enable
          && config.services.meshNetwork.dockerIntegration
          && builtins.elem "backend" entry.networks;
      in
      lib.nameValuePair (lib.removeSuffix ".service" entry.serviceName) {
        unitConfig.OnFailure = lib.mkDefault "infra-update-report@%n.service";
        after = lib.optional usesMeshNetwork "docker-meshNetwork.service";
        requires = lib.optional usesMeshNetwork "docker-meshNetwork.service";
        partOf = lib.optional usesMeshNetwork "docker-meshNetwork.service";
      }
    ) containerEntries
  );

  dockerSshValidator = "${config.system.build.dockerMigrationCommand}/bin/docker-migration-command";
in
{
  imports = [
    "${self}/modules/profiles/meshNetwork"
    "${self}/modules/profiles/infraUpdateReport.nix"
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
      example = [
        "stateful-db"
        "wireguard"
      ];
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
        When true, active containers are restarted only if their running image
        differs from the pulled image. If false, active containers are restarted
        after every successful pull. Inactive services remain stopped.
      '';
    };
  };

  config = lib.mkMerge [
    {
      virtualisation = {
        docker = {
          enable = lib.mkForce true;
          package = lib.mkDefault pkgs.docker_29;
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
        flags = [
          "--filter"
          "until=24h"
        ];
      };

      # Declarative OCI container image maintenance.
      services.infraUpdateReport.enable = lib.mkDefault true;

      systemd.services.docker-container-auto-update = lib.mkIf cfg.enable {
        description = "Update Docker OCI container images from declarative definitions";
        after = [ "docker.service" ];
        unitConfig.OnFailure = "infra-update-report@%n.service";
        serviceConfig = {
          Type = "oneshot";
        };
        path = [
          pkgs.bash
          pkgs.coreutils
          config.virtualisation.docker.package
          pkgs.systemd
        ];
        script = ''
          #!/usr/bin/env bash
          set -euo pipefail

          pull_only=${if cfg.pullOnly then "true" else "false"}
          restart_changed_only=${if cfg.restartChangedOnly then "true" else "false"}

          skip_containers="${skipContainersScript}"

          container_entries="${containerDefinitionsScript}"
          had_failure=0

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

          if [ -z "$container_entries" ]; then
            echo "No OCI containers are configured under virtualisation.oci-containers.containers."
            exit 0
          fi

          while IFS= read -r entry; do
            [ -z "$entry" ] && continue
            IFS='|' read -r container_name container_image container_service <<< "$entry"

            if is_skipped "$container_name"; then
              echo "container_update_event container=$container_name image=$container_image service=$container_service action=skip_policy"
              continue
            fi

            echo "container_update_event container=$container_name image=$container_image service=$container_service action=pull"
            if ! docker pull "$container_image"; then
              echo "Failed to pull image for $container_name ($container_image)"
              echo "container_update_event container=$container_name image=$container_image service=$container_service action=pull_failed"
              had_failure=1
              continue
            fi

            if [[ "$pull_only" == "true" ]]; then
              echo "Pulled image for $container_name; pull-only mode enabled."
              continue
            fi

            unit_name="''${container_service%.service}.service"

            if ! systemctl cat "$unit_name" > /dev/null 2>&1; then
              echo "Container service $unit_name not found."
              had_failure=1
              continue
            fi

            if ! systemctl is-active --quiet "$unit_name"; then
              echo "container_update_event container=$container_name service=$unit_name action=skip_inactive"
              continue
            fi

            # A previous pull (or another container sharing the tag) may already
            # have updated the cache. Compare against the actual running image.
            if ! before_id="$(docker container inspect --format '{{.Image}}' "$container_name")" || [ -z "$before_id" ]; then
              echo "Cannot inspect running image for $container_name."
              had_failure=1
              continue
            fi
            if ! after_id="$(docker image inspect --format '{{.Id}}' "$container_image")" || [ -z "$after_id" ]; then
              echo "Cannot inspect pulled image for $container_name."
              had_failure=1
              continue
            fi
            echo "container_update_event container=$container_name image=$container_image service=$unit_name before_id=$before_id after_id=$after_id action=inspect"

            if [[ "$restart_changed_only" == "true" && "$before_id" == "$after_id" ]]; then
              echo "container_update_event container=$container_name image=$container_image service=$unit_name before_id=$before_id after_id=$after_id changed=false action=skip_restart"
              continue
            fi

            echo "container_update_event container=$container_name image=$container_image service=$unit_name before_id=$before_id after_id=$after_id changed=true action=restart"
            if ! systemctl try-restart "$unit_name"; then
              echo "Failed to restart $unit_name"
              exit 1
            fi
          done <<< "$container_entries"

          if [ "$had_failure" -ne 0 ]; then
            echo "One or more container image updates failed."
            exit 1
          fi
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
        groups.docker = lib.mkForce { };

        users.docker = {
          isSystemUser = lib.mkForce true;
          # SCP/SFTP can write this user's home. A noninteractive SSH command
          # must not execute a writable .bashrc before reaching ForceCommand.
          shell = lib.mkForce pkgs.dash;
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
            {
              command = "${pkgs.openssh}/bin/ssh *";
              options = [
                "NOPASSWD"
                "SETENV"
              ];
            }
            {
              command = "${pkgs.coreutils}/bin/test *";
              options = [ "NOPASSWD" ];
            }
          ];
          runAs = "docker";
        }
      ]
      ++ lib.optional (containerEntries != [ ]) {
        groups = [ "docker" ];
        runAs = "root";
        # OCI containers are removed on stop. Manage their declared units so
        # migration can stop them cleanly and recreate them after the copy.
        commands = lib.concatMap (
          entry:
          map
            (action: {
              command = "${pkgs.systemd}/bin/systemctl ${action} ${lib.removeSuffix ".service" entry.serviceName}.service";
              options = [ "NOPASSWD" ];
            })
            [
              "stop"
              "start"
            ]
        ) containerEntries;
      };

      # Restrict the docker user's SSH access to only SCP/SFTP file transfers
      # and docker commands needed for volume migration. No interactive shell,
      # no port forwarding, no agent forwarding.
      services.openssh.extraConfig = ''
        Match User docker
          DisableForwarding yes
          PermitTTY no
          PermitUserRC no
          AllowTcpForwarding no
          AllowAgentForwarding no
          X11Forwarding no
          PermitTunnel no
          ForceCommand ${dockerSshValidator}
      '';

      # Deploy the SSH private key for the docker user to use when connecting to other hosts.
      # The key is sourced from config.secrets.volumeMigration.file and written with
      # strict permissions (0600, owned by docker:docker) as required by SSH.
      # Keep the parent root-owned and replace the file atomically: SFTP must
      # never be able to redirect a root write via a symlink in docker's home.
      systemd.services.deploy-docker-migration-key = {
        description = "Deploy SSH private key for docker volume migration";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Group = "docker";
          StateDirectory = "docker-volume-migration";
          StateDirectoryMode = "0750";
        };
        script = ''
          set -euo pipefail
          state_dir=/var/lib/docker-volume-migration
          chown root:docker "$state_dir"
          key_tmp=$(mktemp "$state_dir/.identity.XXXXXX")
          trap 'rm -f "$key_tmp"' EXIT
          sed 's/^[[:space:]]*//' "${config.secrets.volumeMigration.file}" > "$key_tmp"
          chmod 600 "$key_tmp"
          chown docker:docker "$key_tmp"
          mv -T "$key_tmp" "$state_dir/identity"
          # Only administrator-provisioned trust is retained. The old
          # docker-owned cache (and home known_hosts) is not verified trust.
          if [ -L "$state_dir/known_hosts" ] || [ ! -f "$state_dir/known_hosts" ] ||
             [ "$(stat -c %u "$state_dir/known_hosts")" != 0 ] ||
             [ "$(find "$state_dir/known_hosts" -maxdepth 0 -perm /022 -print)" != "" ]; then
            trust_tmp=$(mktemp "$state_dir/.known-hosts.XXXXXX")
            trap 'rm -f "$key_tmp" "$trust_tmp"' EXIT
            chmod 640 "$trust_tmp"
            chown root:docker "$trust_tmp"
            mv -fT "$trust_tmp" "$state_dir/known_hosts"
          fi
          chown root:docker "$state_dir/known_hosts"
          chmod 640 "$state_dir/known_hosts"
        '';
      };
    }
    {
      systemd.services = containerFailureServices;
    }
  ];
}
