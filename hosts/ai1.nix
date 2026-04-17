{
  self,
  nixpkgsMaster,
  config,
  lib,
  system,
  pkgs,
  ...
}:
  let
    # Import nixpkgsMaster with config to allow insecure openclaw package
    pkgsMaster = import nixpkgsMaster {
      inherit system;
      config = {
        allowUnfree = true;
        permittedInsecurePackages = [ "openclaw-2026.4.12" ];
      };
    };
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

  # Set nixpkgs config to allow insecure packages
  # This applies to the main pkgs (nixpkgsStable)
  nixpkgs.config = {
    allowUnfree = true;
    permittedInsecurePackages = [ "openclaw-2026.4.12" ];
  };

  # Add overlay to bring openclaw from nixpkgsMaster into main pkgs
  nixpkgs.overlays = [
    (final: prev: {
      openclaw = pkgsMaster.openclaw;
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
  
  # Deploy openclaw config from secrets
  environment.etc."openclaw/openclaw.json" = {
    source = config.secrets.openclaw.file;
    mode = "0600";
  };
  
  # Create shell profile with environment variables for openclaw user
  environment.etc."skel/openclaw-profile" = {
    text = ''
      # OpenClaw environment variables - unified with systemd service
      export OPENCLAW_CONFIG=/etc/openclaw/openclaw.json
      export OPENCLAW_STATE_DIR=/mnt/data/openclaw/.openclaw
      export OPENCLAW_NIX_MODE=1
      export NPM_CONFIG_CACHE=/mnt/data/openclaw/.npm-cache
    '';
    mode = "0644";
  };
  
  # Create required directories and files
  systemd.tmpfiles.rules = [
    "d /mnt/data/openclaw 0755 openclaw openclaw -"
    "d /mnt/data/openclaw/.cache 0755 openclaw openclaw -"
    "d /mnt/data/openclaw/.openclaw 0755 openclaw openclaw -"
    "d /mnt/data/openclaw/.npm-cache 0755 openclaw openclaw -"
    # Copy shell profile
    "C+ /mnt/data/openclaw/.profile 0644 openclaw openclaw - /etc/skel/openclaw-profile"
  ];
  
  # Enable required services
  services = {
    meshNetwork.enable = true;
  };

  environment.systemPackages = with pkgs; [
    nodejs
    uv
    himalaya
    openai-whisper
    jq
    tmux
    ffmpeg

    openclaw
  ];

  # Enable automatic garbage collection to prevent disk space issues
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Optimize Nix settings for AI workloads
  nix.settings = {
    auto-optimise-store = true;
    experimental-features = [ "nix-command" "flakes" ];
  };

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
        "OPENCLAW_STATE_DIR=/mnt/data/openclaw/.openclaw"
        "OPENCLAW_CONFIG=/etc/openclaw/openclaw.json"
        # Set npm cache to data partition to avoid filling root filesystem
        "NPM_CONFIG_CACHE=/mnt/data/openclaw/.npm-cache"
      ];
      ExecStart = "${pkgs.openclaw}/bin/openclaw gateway --port 18789 --bind loopback --allow-unconfigured --auth none";
      Restart = "always";
    };
  };
}