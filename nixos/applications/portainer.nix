{ config, lib, pkgs, ... }:

{
  # 1) Deploy Portainer using oci-container interface
  systemd.services.portainer = {
    description = "Portainer container management UI (Podman)";
    after = [ "network.target" "podman.socket" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "podman";
      ExecStart = ''
        ${pkgs.podman}/bin/podman run \
          --name portainer \
          -p 9000:9000 \
          -v portainer_data:/data \
          -v /run/podman/podman.sock:/var/run/docker.sock \
          docker.io/portainer/portainer-ce:latest
      '';
      ExecStop = "${pkgs.podman}/bin/podman stop portainer";
      Restart = "always";
    };
  };
  # virtualisation.oci-containers.containers.portainer = {
  #   image = "docker.io/portainer/portainer-ce:latest";
  #   ports = [ "9000:9000" ];
  #   volumes = [
  #     "portainer_data:/data"
  #     "/run/podman/podman.sock:/var/run/docker.sock"
  #   ];
  #   # networks = [
  #   #   "backend"
  #   # ];

  #   autoStart = true;
  #   serviceName = "portainer";

  #   podman.user = lib.mkIf (config.virtualisation.podman.enable) "podman";
  # };

  # Allow firewall access to Portainer (port 9000)
  networking.firewall.allowedTCPPorts = [ 9000 ];
}
