{
  defaultStateVersion,
  self,
  nixpkgs ? self.inputs.nixpkgsStable,
}: host: {
  modules ? [],
  system ? "x86_64-linux",
  hardware ? "qemu",
}: nixpkgs.lib.nixosSystem {
  inherit system;
  
  specialArgs = {
    inherit self
      system
      defaultStateVersion;
    inherit (self.inputs) nixpkgsUnstable nixpkgsMaster;
    inherit (nixpkgs) lib;
  };
  modules = modules ++ [
    "${self}/modules/hardware/${hardware}.nix"
    "${self}/modules/profiles/standard.nix"
    "${self}/modules/profiles/firewall.nix"
    (if host == "standard" then {} else {
      imports = [ 
        "${self}/hosts/${host}.nix"
      ] ++ (if builtins.pathExists "${self}/modules/secrets/${host}.nix" then [ "${self}/modules/secrets/${host}.nix" ] else []);
    })
    {
      system.stateVersion = nixpkgs.lib.mkDefault defaultStateVersion;
    }
  ];
}