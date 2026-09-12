{
  defaultStateVersion,
  self,
  nixpkgs ? self.inputs.nixpkgsStable,
}: host: {
  # Common configuration
  system ? "x86_64-linux",
  hardware ? "qemu",
  modules ? [],
  includeSecrets ? true,
  
  # VMA-specific configuration (optional)
  vmId ? null,
  cores ? 2,
  memory ? 4096,
  enableProtection ? true,
  disks ? [
    {
      storage = "hotData";
      size = 25;
    }
  ],
  networking ? [
    {
      bridge = "vmbr0";
      firewall = false;
      vlan = 200;
      useDHCP = true;
    }
  ],
  
  # Control what to export
  exportVMA ? true,
  exportNixOS ? true,
}: 
let
  # Import existing library functions
  generateVMAImage = import "${self}/library/generateVMAImage" {
    inherit defaultStateVersion self nixpkgs;
  };
  
  makeConfiguration = import "${self}/library/makeConfiguration.nix" {
    inherit defaultStateVersion self nixpkgs;
  };
  
  # Common filtered args for makeConfiguration (remove VMA-specific args)
  nixosArgs = {
    inherit system hardware modules includeSecrets;
  };
  
  # Full args for VMA generation
  vmaArgs = {
    inherit system hardware vmId cores memory enableProtection disks networking;
    # Images are distributable artifacts. Evaluate them with non-secret example
    # modules so live credentials can never enter the image or build closure.
    includeSecrets = false;
    modules = modules ++ nixpkgs.lib.optional
      (builtins.pathExists "${self}/modules/secrets.example/${host}.nix")
      "${self}/modules/secrets.example/${host}.nix";
  };
  
in {
  # Export VMA package if requested and vmId is provided
  package = if exportVMA && vmId != null 
    then generateVMAImage host vmaArgs
    else throw "Cannot export VMA package: vmId is required when exportVMA is true";
  
  # Export nixosSystem if requested
  nixosSystem = if exportNixOS
    then makeConfiguration host nixosArgs
    else throw "Cannot export nixosSystem: exportNixOS is false";
}
