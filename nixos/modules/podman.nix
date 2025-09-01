{ config, pkgs, ... }:
{
	# Install Podman
	virtualisation.podman = {
		enable = true;
		dockerCompat = true; # Optional: allow 'docker' CLI to use podman
		defaultNetwork.settings.dns_enabled = true; # Enable DNS for networking
		dockerSocket.enable = true; # Enable Docker compatibility socket
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
