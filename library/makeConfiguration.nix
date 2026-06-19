{
  defaultStateVersion,
  self,
  nixpkgs ? self.inputs.nixpkgsStable,
}: host: {
  modules ? [],
  system ? "x86_64-linux",
  hardware ? "qemu",
}:
let
  inTreeSecrets = "${self}/modules/secrets/${host}.nix";
  externalSecretsDir = builtins.getEnv "INFRA_SECRETS_DIR";
  externalSecrets = "${externalSecretsDir}/${host}.nix";
  secretImports =
    if host == "standard" then []
    else if builtins.pathExists inTreeSecrets then [ inTreeSecrets ]
    else if externalSecretsDir != "" && builtins.pathExists externalSecrets then [ externalSecrets ]
    else if externalSecretsDir != "" then
      builtins.throw "Host secret module not found for '${host}': ${externalSecrets}"
    else [];
in
nixpkgs.lib.nixosSystem {
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
      ] ++ secretImports;
    })
    {
      system.stateVersion = nixpkgs.lib.mkDefault defaultStateVersion;
    }
  ];
}
