# modules/docker.nix
# Installs and configures Docker according to best practices.
{ config, pkgs, lib, ... }:
{
  # 1) Install Docker
  virtualisation.docker = {
    enable = true;
  };
  boot.kernelParams = lib.mkIf (!config.boot.isContainer) [ "systemd.unified_cgroup_hierarchy=1" ];

  # 2) Mount secondary disk to /var/lib/docker/volumes
  fileSystems = {
    "/var/lib/docker/volumes" = {
      device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1";
      fsType = "ext4";
      options = [ "defaults" ];

      autoResize = true;
      autoFormat = true;
    };
  };

  # 3) Create a dedicated docker system user
  users = {
    groups.docker = {};

    users = {
      docker = {
        isSystemUser = true;
        shell = "${pkgs.shadow}/bin/nologin";
        home = "/var/lib/docker";
        group = "docker";
        # User must be managed using sudo
        initialHashedPassword = "!";
      };
    };
  };
}
