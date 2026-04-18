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
    bash
    nodejs
    git
    curl
    uv
    himalaya
    openai-whisper
    jq
    tmux
    ffmpeg
  ];

  systemd.services.openclaw-gateway = {
    description = "OpenClaw AI Assistant Gateway";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    
    # Pre-start script to copy source and install dependencies with network access
    preStart = ''
      # Copy openclaw source if not already present
      if [ ! -f /mnt/data/openclaw/package.json ]; then
        mkdir -p /mnt/data/openclaw
        cp -r ${openclaw}/lib/openclaw/* /mnt/data/openclaw/
        chown -R openclaw:openclaw /mnt/data/openclaw
      fi
      
      # Install dependencies if needed (with network access enabled here)
      if [ ! -d /mnt/data/openclaw/node_modules ]; then
        cd /mnt/data/openclaw
        # Ensure git, curl, node, and sh are available for npm's dependency resolution and postinstall scripts
        export PATH="${pkgs.nodejs}/bin:${pkgs.git}/bin:${pkgs.curl}/bin:${pkgs.bash}/bin:$PATH"
        ${pkgs.nodejs}/bin/npm install --legacy-peer-deps
        chown -R openclaw:openclaw /mnt/data/openclaw/node_modules
      fi
    '';
    
    serviceConfig = {
      User = "openclaw";
      Group = "openclaw";
      WorkingDirectory = "/mnt/data/openclaw";
      # Use npm start or node with appropriate entry point
      ExecStart = "${pkgs.nodejs}/bin/npm start -- gateway";
      Restart = "always";
    };
  };
}