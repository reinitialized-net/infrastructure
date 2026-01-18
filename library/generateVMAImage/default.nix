{
  defaultStateVersion,
  self,
  lib ? self.inputs.nixpkgsStable.lib,
  modulesPath ? "${self.inputs.nixpkgsStable}/nixos/modules",
}: host: {
  vmId,
  modules ? [],
  cores ? 2,
  memorySize ? 4096,
  disks ? {
    storage = "hotData";
    gbSize = 25;
  },
  networking ? {
    hostName = "nixVMA";
    bridge = "vmbr0";
    firewall = 0;
    useDHCP = true;
    ipAddress = null;
  }
}:
let

in {
}