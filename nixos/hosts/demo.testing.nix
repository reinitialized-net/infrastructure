# Host Configuration for mgnt.portainer
{ config, ... }:

{
  # 1) Import required modules
  imports = [
    ../hardware/qemu.nix
    ../profiles/standard.nix

    ../modules/podman.nix
  ];

  # 2) Adjust system properties
  networking.hostName = "admin";
  
  # 3) Deploy Portainer using oci-container interface
  virtualisation.oci-containers.containers.portainer = {
    image = "docker.io/portainer/portainer-ce:latest";
    ports = [ "9000:9000" ];
    volumes = [
      "portainer_data:/data"
      "/run/podman/podman.sock:/var/run/docker.sock"
    ];

    autoStart = true;
    serviceName = "portainer";

    podman.user = lib.mkIf (config.virtualisation.podman.enable) "containers";
  };
}