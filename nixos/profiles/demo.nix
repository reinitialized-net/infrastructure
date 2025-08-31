# profiles/demo.nix
## A demostration profile for testing Nix configurations
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = 
    [
      ../hardware/qemu.nix
      ../modules/standard.nix

      ../modules/podman.nix
    ];
}