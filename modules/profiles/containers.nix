{
  self,
  lib,
  config,
  pkgs,
  ...
}: {
  assertions = [
    {
      assertion = "";
      message = "${self}/modules/profiles/mountData.nix is not loaded, which is required by ${self}/modules/profiles/containers.nix";
    }
  ];

  imports = [
    "${self}/modules/profiles/meshNetwork"
  ];

  virtualisation = {
    docker = {
      enable = lib.mkForce true;
      daemon.settings = {
        icc = lib.mkForce true;
        no-new-privileges = lib.mkForce true;
      };
    };
    oci-containers.backend = lib.mkForce "docker";
  };

  boot.kernelParams = lib.mkIf (!config.boot.isContainer) [ "systemd.unified_cgroup_hierarchy=1" ];

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
      home = lib.mkForce "/var/lib/docker";
      group = lib.mkForce "docker";
      initialHashedPassword = lib.mkForce "!";
    };
  };

}