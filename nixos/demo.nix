# profiles/demo.nix
## A demostration profile for testing Nix configurations
{ config, ... }:
{
  imports = 
    [
      ./hardware/qemu.nix
      ./modules/standard.nix

      ./modules/podman.nix
      ./modules/portainer.nix
    ];
}