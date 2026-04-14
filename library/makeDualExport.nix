{
  defaultStateVersion,
  self,
  nixpkgs ? self.inputs.nixpkgsStable,
}: host: {
  # Common configuration
  system ? "x86_64-linux",
  hardware ? "qemu",
  modules ? [],
  
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
    inherit system hardware modules;
  };
  
  # Full args for VMA generation
  vmaArgs = {
    inherit system hardware modules vmId cores memory enableProtection disks networking;
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
