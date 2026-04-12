{
  self,
  lib,
  system,
  pkgs,
  ...
}:{
  imports = [
    (import "${self}/library/makeUser.nix" {
      username = "llamacpp";
      group = "llamacpp";
      homeDirectory = "/var/lib/llamacpp";
      dataPath = "/mnt/data/llamacpp";
      extraUserAttrs = {
        isSystemUser = true;
        description = "llama.cpp service user";
      };
    })
    (import "${self}/library/makeUser.nix" {
      username = "openclaw";
      group = "openclaw";
      homeDirectory = "/var/lib/openclaw";
      dataPath = "/mnt/data/openclaw";
      extraUserAttrs = {
        isSystemUser = true;
        description = "OpenClaw service user";
      };
    })
  ];
  # Networking Configuration
  networking = {
    hostName = "ai1";
    useDHCP = false;
    firewall.enable = true;

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
  
  # Create required files
  systemd.tmpfiles.rules = [
    "d /mnt/data/llamacpp/.cache 0755 llamacpp llamacpp -"
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
      Environment = [
        "LLAMA_CACHE_DIR=/mnt/data/llamacpp/.cache"
        "HOME=/var/lib/llamacpp"
        "XDG_CACHE_HOME=/mnt/data/llamacpp/.cache"
      ];
      ExecStart = "${pkgs.callPackage "${self}/modules/packages/llama-cpp.nix" { acceleration = false; }}/bin/llama-server "
        + "-hf unsloth/gemma-4-26B-A4B-it-GGUF:UD-Q8_K_XL "
        + "--host 0.0.0.0 "
        + "--port 8080 "
        + "--embedding "
        + "-ngl 0";
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
