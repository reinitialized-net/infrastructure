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

  # Allow insecure packages
  nixpkgs.config.permittedInsecurePackages = [
    "openclaw-2026.4.15"
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
    bash
    coreutils
    nodejs
    pnpm
    git
    curl
    uv
    himalaya
    openai-whisper
    jq
    tmux
    ffmpeg
  ];

  systemd.services.swap-setup = {
    description = "Setup 16GB swap file for memory-intensive builds";
    after = [ "local-fs.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = "PATH=/run/current-system/sw/bin:/usr/bin:/bin";
    };
    script = ''
      if [ ! -f /mnt/data/swapfile ] || [ $(stat -c%s /mnt/data/swapfile) -lt 68719476736 ]; then
        echo "Creating 64GB swap file on /mnt/data..."
        swapoff /mnt/data/swapfile || true
        dd if=/dev/zero of=/mnt/data/swapfile bs=1M count=65536
        chmod 600 /mnt/data/swapfile
        mkswap /mnt/data/swapfile
        swapon /mnt/data/swapfile
        echo "Swap file created and activated."
      fi
    '';
  };

  systemd.services.openclaw-build = {
    description = "Build OpenClaw from source on host";
    after = [ "network.target" "swap-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "openclaw";
      Group = "openclaw";
      WorkingDirectory = "/mnt/data/openclaw";
      Environment = "PATH=/run/current-system/sw/bin:${pkgs.nodejs}/bin:${pkgs.pnpm}/bin:${pkgs.git}/bin:${pkgs.bash}/bin:/usr/local/bin:/usr/bin:/bin";
    };
    script = ''
      # Copy openclaw source if not already present
      if [ ! -f /mnt/data/openclaw/package.json ]; then
        mkdir -p /mnt/data/openclaw
        cp -r ${openclaw}/lib/openclaw/* /mnt/data/openclaw/
        chown -R openclaw:openclaw /mnt/data/openclaw
      fi

      # Build on host to avoid OOM on devenv
      if [ ! -f /mnt/data/openclaw/dist/entry.mjs ] && [ ! -f /mnt/data/openclaw/dist/entry.js ]; then
        ${openclaw}/bin/openclaw-build /mnt/data/openclaw
      else
        echo "Openclaw already built, skipping."
      fi
    '';
  };

  systemd.services.openclaw-gateway = {
    enable = true;
    description = "OpenClaw AI Assistant Gateway";
    after = [ "network.target" "openclaw-build.service" ];
    requires = [ "openclaw-build.service" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      User = "openclaw";
      Group = "openclaw";
      WorkingDirectory = "/mnt/data/openclaw";
      # Ensure PATH includes all required binaries
      Environment = "PATH=${pkgs.nodejs}/bin:${pkgs.git}/bin:${pkgs.curl}/bin:${pkgs.bash}/bin:/usr/local/bin:/usr/bin:/bin";
      # Startup timeout for initial operations
      TimeoutStartSec = 120;
      # Run openclaw CLI directly - entry point is openclaw.mjs (created during build)
      ExecStart = "${pkgs.nodejs}/bin/node openclaw.mjs gateway";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}