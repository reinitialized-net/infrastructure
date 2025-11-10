{ nixpkgs, inputs }:

host: {
  system ? "x86_64-linux",
  modules ? [],
  hardware ? "qemu",
}:

let
  # Define systemState for all configurations (DO NOT CHANGE)
  systemState = "25.05";
  # Bring in hardware module
  hardwareModule = import ./hardware/${hardware}.nix;
  # Bring in host module
  hostModule = import ./hosts/${host}.nix;
in nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = {
    inherit inputs;
  };
  # Declare modules
  modules = modules ++ [
    hardwareModule
    hostModule
    {
      ## Inject global stateVersion
      stateVersion = systemState;
    }
  ];
}