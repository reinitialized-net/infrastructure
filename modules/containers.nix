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
      autoResize = true;
      autoFormat = true;

      device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1";
      fsType = "ext4";
      options = [ "defaults" ];
    };
    "/var/lib/docker/volumes" = {
      depends = [ "/mnt/data" ];
      device = "/mnt/data/docker/volumes";
      fsType = "none";
      options = [ "bind" ];
    };
  };
  # Create dedicated user for managing Docker
  users = {
    groups = {
      docker = {};
    };
    users = {
      docker = {
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