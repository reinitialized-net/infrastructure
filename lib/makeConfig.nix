{ nixpkgs, inputs }:
host: {
  modules ? [],
  system ? "x86_64-linux",
  hardware ? "qemu",
}:
let
  # Standardize system.stateVersion (DO NOT CHANGE)
  defaultStateVersion = "25.05";

in nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = {
    inherit inputs;
    inherit defaultStateVersion;
  };
  # Declare modules
  modules = modules ++ [
    ../extensions/firewall.nix
    ../modules/standard.nix
    ../hardware/${hardware}.nix
    ../hosts/${host}.nix
    {
      system.stateVersion = defaultStateVersion;
    }
  ];
}