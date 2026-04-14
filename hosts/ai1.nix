{
  self,
  nixpkgsUnstable,
  config,
  lib,
  system,
  pkgs,
  ...
}:
  let
    pkgsUnstable = import nixpkgsUnstable {
      system = system;
      config = {
        permittedInsecurePackages = [ "openclaw-2026.4.2" ];
      };
    };
  in {
  imports = [
    (import "${self}/library/makeUser.nix" {
      username = "openclaw";
      group = "openclaw";
      homeDirectory = "/var/lib/openclaw";
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
  
  # Create required files
  systemd.tmpfiles.rules = [
    "d /mnt/data/openclaw/.cache 0755 openclaw openclaw -"
    "d /mnt/data/openclaw/state 0755 openclaw openclaw -"
  ];
  # Enable required services
  services = {
    meshNetwork.enable = true;
  };

  environment.systemPackages = [
    pkgs.nodejs_24
    pkgsUnstable.openclaw
  ];

  systemd.services.openclaw = {
    description = "OpenClaw AI Assistant Gateway";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "openclaw";
      Group = "openclaw";
      WorkingDirectory = "/mnt/data/openclaw";
      Environment = [
        "OPENCLAW_NIX_MODE=1"
        "OPENCLAW_STATE_DIR=/mnt/data/openclaw"
        "OPENCLAW_CONFIG_PATH=${config.secrets.openclaw.file}"
        "OPENCLAW_CONTROL_UI_ALLOWED_ORIGINS=*"
      ];
      ExecStart = "${pkgsUnstable.openclaw}/bin/openclaw gateway run --allow-unconfigured --bind lan --allow-origins *";
      Restart = "always";
    };
  };
}