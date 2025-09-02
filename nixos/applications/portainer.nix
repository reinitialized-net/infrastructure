{ config, lib, pkgs, ... }:

{
  # 1) Deploy Portainer using oci-container interface
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

  # Allow firewall access to Portainer (port 9000)
  networking.firewall.allowedTCPPorts = [ 9000 ];
}
