{
  self,
  lib,
  pkgs,
  ...
}: {
  assertions = [
    {
      assertion = "";
      message = "${self}/modules/profiles/mountData.nix is not loaded, which is required by ${self}/modules/profiles/containers.nix";
    }
  ];

  virtualisation = {
    enable = lib.mkForce true;
    daemon.settings = {
      icc = lib.mkForce true;
      no-new-privileges = lib.mkForce true;
    };
    oci-containers.backend = lib.mkForce "docker";
  };

  fileSystems = {
    "/var/lib/docker" = lib.mkForce {
      device = "/mnt/data/docker";
      depends = [ "/mnt/data/docker/volumes" ];
      fsType = "none";
      options = [ "bind" ];
    };
  };
}