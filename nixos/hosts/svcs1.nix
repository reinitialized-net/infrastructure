# Host Configuration for mgnt.portainer
{ config, lib, ... }:

{
  # 1) Import required modules
  imports = [
    ../hardware/qemu.nix
    ../profiles/standard.nix

    ../modules/podman.nix
  ];

  # 2) Adjust system properties
  networking.hostName = "devenv";
  
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

  # 4) Allow firewall access to Services
  networking.firewall.allowedTCPPorts = [ 9000 ];
}