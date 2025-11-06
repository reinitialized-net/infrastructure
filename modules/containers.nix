# modules/docker.nix
# Docker module with security hardening and best practices
{ config, pkgs, lib, ... }:
{
  # Install/Configure Docker
  virtualisation = {
    docker = {
      enable = true;
      daemon = {
        settings = {
          # Disable inter-container communication on default bridge
          icc = true;
          # Reduce privilege escalation risks
          no-new-privileges = true;
        };
      };
    };
    oci-containers = {
      backend = "docker";
    };
  };
  boot.kernelParams = lib.mkIf (!config.boot.isContainer) [ "systemd.unified_cgroup_hierarchy=1" ];
  # Mount secondary drive for Containers
  fileSystems = {
    "/mnt/data" = {
      device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1";
      fsType = "ext4";
      options = [ "defaults" ];

      autoResize = true;
      autoFormat = true;
    };
  };
  # Symlink /var/lib/docker/volumes to /mnt/data/docker/volumes
  systemd.tmpfiles.rules = [
    "L+ /var/lib/docker/volumes /mnt/data/docker/volumes"
  ];
  # Create dedicated user for managing Docker
  users = {
    groups = {
      docker = {};
    };

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
  system = {
    activationScripts = {
      # Ensure Docker network 'backend' exists
      ensureDockerNetwork = {
        text = ''
          if ! ${pkgs.docker}/bin/docker network inspect backend &>/dev/null; then
            ${pkgs.docker}/bin/docker network create backend
          fi
        '';
      };
    };
  };
}