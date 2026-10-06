{
  ...
}:
{
  # Qwen3.8 on the passed-through GTX 1070 (docs/llm1.md)
  imports = [
    ./llm1/llm.nix
  ];
  # Networking Configuration
  networking = {
    hostName = "llm1";
    useDHCP = false;
  };
  systemd.network.networks = {
    "eth0" = {
      address = [
        "10.1.11.9/24"
      ];
      dns = [
        "10.1.11.2"
        "10.1.11.3"
      ];
      ntp = [
        "10.1.11.1"
      ];
      gateway = [
        "10.1.11.1"
      ];
      matchConfig.Path = "pci-0000:06:12.0";
    };
  };
  # Configure MeshNetwork
  services.meshNetwork = {
    enable = true;
  };
}
