{ nixpkgs, inputs }:
host: {
  system ? "x86_64-linux",
  modules ? [],
  hardware ? "qemu",
}:
let
  # Define defaultStateVersion (DO NOT CHANGE)
  defaultStateVersion = "25.05";
in nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = {
    inherit inputs;
    inherit defaultStateVersion;
  };
  # Declare modules
  modules = modules ++ [
    import ../hardware/${hardware}.nix
    import ../hosts/${host}.nix
    {
      system.stateVersion = defaultStateVersion;
    }
  ];
}