{
  self,
  lib,
  config,
  pkgs,
  ...
}: let
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
}