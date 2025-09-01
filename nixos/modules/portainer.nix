{ config, pkgs, ... }:

{
  # Install Portainer (as a container managed by Podman)
  systemd.services.portainer = {
    description = "Portainer container management UI (Podman)";
    after = [ "network.target" "podman.socket" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "podman";
      ExecStart = ''
        ${pkgs.podman}/bin/podman run --rm \
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

  # Allow firewall access to Portainer (port 9000)
  networking.firewall.allowedTCPPorts = [ 9000 ];
}
