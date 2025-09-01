{ config, pkgs, ... }:
{
	# Install Podman
	virtualisation.podman = {
		enable = true;
		dockerCompat = true; # Optional: allow 'docker' CLI to use podman
		defaultNetwork.settings.dns_enabled = true;
		socket.enable = true; # Enable the Podman socket for Portainer
	};
	# Create a dedicated podman user (system user, no login)
  users = {
    groups.podman = {};

    users = {
      podman = {
        isSystemUser = true;
        createHome = true;
        home = "/var/lib/podman";
        shell = pkgs.shadow + "/bin/nologin";
        group = "podman";
        extraGroups = [ "podman" ];
      };
    };
  };
}
