# modules/podman.nix
# Installs and configures Podman according to best practices.
{ config, lib, pkgs, ... }:
{
  # 1) Install Podman
    virtualisation = {
    podman = {
      enable = true;
      # Optional: allow 'docker' CLI to use podman
      dockerCompat = true;
      # Optional: Enable DNS for networking
      defaultNetwork.settings.dns_enabled = true;
      # Optional: Enable Docker compatibility socket (eg. for Portainer)
      dockerSocket.enable = lib.mkDefault false;
    };
    oci-containers.backend = "podman";
  };
  boot.kernelParams = lib.mkIf (!config.boot.isContainer) [ "systemd.unified_cgroup_hierarchy=1" ];

  # 2) Mount secondary disk to /var/lib/containers/storage/volumes
  fileSystems = {
    "/var/lib/containers/storage/volumes" = {
      device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1";
      fsType = "ext4";
      options = [ "defaults" ];

      autoResize = true;
      autoFormat = true;
    };
  };

	# 3) Create a dedicated user for managing containers
  users = {
    groups.podman = {};

    users = {
      containers = {
        isSystemUser = true;
        shell = pkgs.bash;
        home = "/var/lib/containers";
        group = "podman";
        # User must be managed using sudo
        initialHashedPassword = "!";
      };
    };
  };

  # 4) Create container-init service
  systemd.services.container-init = {
    description = "Perform Container initialization";
    after = [ "podman.service" ];
    wantedBy = [ "multi-user.target" ];
    script = ''
      #!/usr/bin/env bash
      if ! ${pkgs.podman}/bin/podman network exists backend; then
        ${pkgs.podman}/bin/podman network create backend
      fi

      chown -R containers:containers /var/lib/containers
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };
}
