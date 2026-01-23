{
  self,
  pkgs,
  ...
}:{
  # Networking Configuration
  networking = {
    hostName = "rp1";
    useDHCP = false;
    firewall.whitelist = [
      {
        port = 80;
        protocol = "tcp_udp";
        ipType = "ipv4";
        source = [ "0.0.0.0/0" ];
      }
      {
        port = 443;
        protocol = "tcp_udp";
        ipType = "ipv4";
        source = [ "0.0.0.0/0" ];
      }
    ];
  };
  systemd.network.networks = {
    "eth0" = {
      address = [
        "10.1.12.2/29"
        #10.1.12.3/29
        "10.1.12.4/29"
      ];
      dns = [
        "10.1.12.3"
        #"10.1.11.2"
        #"10.1.11.3"
      ];
      gateway = [
        "10.1.12.1"
      ];
      matchConfig.Path = "pci-0000:06:12.0";
    };
  };
  # Configure MeshNetwork
  services.meshNetwork = {
    enable = true;
    nodeId = 2;
    
    peers = [
      {
        nodeId = 1;
        endpoint = "10.1.200.2:51820";
        publicKey = "zKEWyw9tClll136BGRSv2ImwiP6wNpeJ8ZqG6+ETnmY=";
      }
    ];
  };
}