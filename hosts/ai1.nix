{
  self,
  lib,
  system,
  pkgs,
  ...
}:{
  # Networking Configuration
  networking = {
    hostName = "ai1";
    useDHCP = false;

    firewall.allowlist = [
      {
        port = 8080;
        protocol = "tcp_udp";
        ipType = "ipv4";
        source = [
          "10.0.0.0/8"
          "172.16.0.0/24"
          "192.168.0.0/16"
        ];
      }
    ];
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

  nixpkgs.config.allowUnfreePredicate = pkg: false;
  # Create dedicated users
  users = {
    groups = {
      llamacpp = {};
      openclaw = {};
    };

    users = {
      llamacpp = {
        isSystemUser = true;
        group = "llamacpp";
        description = "llama.cpp service user";
      };
      openclaw = {
        isSystemUser = true;
        group = "openclaw";
        description = "OpenClaw service user";
      };
    };
  };
  # Create required files
  systemd.tmpfiles.rules = [
    "d /mnt/data/models 0755 llamacpp llamacpp -"
  ];
  # Enable required services
  services = {
    meshNetwork.enable = true;
  };

  environment.systemPackages = [
    pkgs.nodejs_24
  ];

  systemd.services.llama-cpp-server = {
    description = "llama.cpp server";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "llamacpp";
      Group = "llamacpp";
      ExecStart = "${pkgs.callPackage "${self}/modules/packages/llama-cpp.nix" { acceleration = false; }}/bin/llama-server "
        + "-m /mnt/data/models/model.gguf "
        + "--host 0.0.0.0 "
        + "--port 8080 "
        + "--embedding "
        + "--ctx-size 4096";
      Restart = "always";
    };
  };

  systemd.services.openclaw = {
    description = "OpenClaw AI Assistant Gateway";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "openclaw";
      Group = "openclaw";
      ExecStart = "${pkgs.nodejs_24}/bin/npx openclaw gateway start";
      Restart = "always";
    };
  };
}
