# profiles/demo.nix
## A demostration profile for testing Nix configurations
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = 
    [
      "${modulesPath}/hardware/qemu.nix"
      "${modulesPath}/modules/standard.nix"

      "${modulesPath}/modules/podman.nix"
    ];
}