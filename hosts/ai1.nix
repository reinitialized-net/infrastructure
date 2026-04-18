{
  self,
  nixpkgsMaster,
  lib,
  system,
  pkgs,
  ...
}:
  let
    openclaw = pkgs.callPackage ../modules/packages/openclaw.nix { };
  in {
  imports = [

    (import "${self}/library/makeUser.nix" {
      username = "openclaw";
      group = "openclaw";
      homeDirectory = "/mnt/data/openclaw";
      dataPath = "/mnt/data/openclaw";
      extraGroups = lib.mkDefault [ "wheel" ];
      extraUserAttrs = {
        isSystemUser = true;
        description = "OpenClaw service user";
        shell = "${pkgs.bash}/bin/bash";
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
        port = 18789;
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
  
  # Create required directories and files
  systemd.tmpfiles.rules = [
    "d /mnt/data/openclaw 0755 openclaw openclaw -"
    "d /mnt/data/openclaw/.cache 0755 openclaw openclaw -"
    "d /mnt/data/openclaw/.openclaw 0755 openclaw openclaw -"
    "d /mnt/data/openclaw/.npm-cache 0755 openclaw openclaw -"
  ];
  
  # Enable required services
  services = {
    meshNetwork.enable = true;
  };

  environment.systemPackages = with pkgs; [
    openclaw
    nodejs
    uv
    himalaya
    openai-whisper
    jq
    tmux
    ffmpeg

    openclaw
  ];

  systemd.services.openclaw-gateway = {
    description = "OpenClaw AI Assistant Gateway";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "openclaw";
      Group = "openclaw";
      WorkingDirectory = "/mnt/data/openclaw";
      ExecStart = "${openclaw}/bin/openclaw gateway";
      Restart = "always";
    };
  };
}