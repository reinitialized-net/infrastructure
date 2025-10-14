# modules/docker.nix
# Docker module with security hardening and best practices
{ config, pkgs, lib, ... }:
{
  # Install/Configure Docker
  virtualisation = {
    docker.enable = true;
    oci-containers.backend = "docker";
  };
  boot.kernelParams = lib.mkIf (!config.boot.isContainer) [ "systemd.unified_cgroup_hierarchy=1" ];
  # Mount secondary drive for Docker volumes
  fileSystems = {
    "/var/lib/docker/volumes" = {
      device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1";
      fsType = "ext4";
      options = [ "defaults" ];

      autoResize = true;
      autoFormat = true;
    };
  };
  # Create dedicated user for managing Docker
  users = {
    groups.docker = {};

    users = {
      containers = {
        isSystemUser = true;
        shell = pkgs.bash;
        home = "/var/lib/docker";
        group = "docker";
        # User must be managed using sudo
        initialHashedPassword = "!";
      };
    };
  };
  # Enable Docker service
  services.docker = {
    enable = true;
    extraOptions = [
      "--icc=false"
      "--no-new-privileges"
    ];
    defaultNetwork = "backend";
  };
  # Ensure the backend network exists
  systemd.services.docker-init = {
    description = "Ensure Docker backend network exists";
    after = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    script = ''
      #!/usr/bin/env bash
      if ! ${pkgs.docker}/bin/docker network inspect backend &>/dev/null; then
        ${pkgs.docker}/bin/docker network create backend
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };
}