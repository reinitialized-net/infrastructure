{
  lib,
  ...
}: {
  fileSystems = {
    "/mnt/data" = lib.mkForce {
      label = "data";
      fsType = "ext4";
      options = [ "defaults"];

      autoFormat = true;
      autoResize = true;
    };
  };
}