{
  self,
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.services.meshNetwork;
  meshInterface = "wg-mesh";
  meshSubnet = "10.255.0.0/24"; # Adjust as needed
  
  # Check if secrets.meshNetwork is configured
  hasSecrets = config.secrets ? meshNetwork;
  secretsCfg = if hasSecrets then config.secrets.meshNetwork else {};
in {
  imports = [ 
    "${self}/modules/profiles/meshNetwork/meshTools.nix"
    "${self}/modules/profiles/secrets.nix"  
  ];

  options.services.meshNetwork = {
    enable = lib.mkEnableOption "Wireguard mesh network for Docker nodes";

    nodeId = lib.mkOption {
      type = lib.types.int;
      description = ''
        Unique node ID (1-254) for this mesh member.
      '';
      example = 1;
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 51820;
      description = ''
        Wireguard listen port.
      '';
    };

    peers = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          nodeId = lib.mkOption {
            type = lib.types.int;
            description = "Node ID of the peer (1-254)";
          };

          publicKey = lib.mkOption {
            type = lib.types.str;
            description = "Wireguard public key of the peer";
          };

          endpoint = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Endpoint address (IP:port) for the peer. Required for at least one node to initiate connections.";
            example = "192.168.1.100:51820";
          };

          persistentKeepalive = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = 25;
            description = "Persistent keepalive interval in seconds. Set to null to disable.";
          };
        };
      });
      default = [];
      description = ''
        List of mesh network peers.
        Can be automatically sourced from secrets.meshNetwork.keys.peers if configured.
      '';
    };

    dockerIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Docker integration with the mesh network";
    };
  };

  config = lib.mkMerge [
    # Main configuration
    (lib.mkIf cfg.enable (lib.mkMerge [
    {
      networking.firewall = {
        allowedUDPPorts = [ cfg.listenPort ];
        trustedInterfaces = [ meshInterface ];
      };

      networking.wireguard.interfaces.${meshInterface} = {
        ips = [ "10.255.0.${toString cfg.nodeId}/24" ];
        listenPort = cfg.listenPort;
        privateKeyFile = secretsCfg.file;

        peers = builtins.map (peer: {
          publicKey = peer.publicKey;
          allowedIPs = [ "10.100.0.${toString peer.nodeId}/32" ];
          endpoint = lib.mkIf (peer.endpoint != null) peer.endpoint;
        persistentKeepalive = lib.mkIf (peer.persistentKeepalive != null) peer.persistentKeepalive;
      }) cfg.peers;
    };

    # Configure WireGuard interface with networkd for routing
    systemd.network.networks."50-${meshInterface}" = {
      matchConfig.Name = meshInterface;
      networkConfig = {
        Address = "10.255.0.${toString cfg.nodeId}/24";
      };
      routeConfig = {
        Destination = meshSubnet;
        Scope = "link";
      };
    };

    # Docker integration
    virtualisation.docker = lib.mkIf (cfg.dockerIntegration && config.virtualisation.docker.enable) {
      daemon.settings = {
        # Add mesh network to Docker daemon
        bip = lib.mkDefault "172.17.0.1/16";
        fixed-cidr = lib.mkDefault "172.17.0.0/16";
      };
    };

    # Enable nftables for Docker integration
    networking.nftables = lib.mkIf cfg.dockerIntegration {
      enable = true;
    };

    # Create a Docker network that routes through mesh
    systemd.services.docker-meshNetwork = lib.mkIf (cfg.dockerIntegration && config.virtualisation.docker.enable) {
      description = "Create Docker mesh network";
      after = [ "docker.service" "wireguard-${meshInterface}.service" "nftables.service" ];
      wants = [ "wireguard-${meshInterface}.service" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        # Wait for Docker daemon
        until ${pkgs.docker}/bin/docker info > /dev/null 2>&1; do
          echo "Waiting for Docker daemon..."
          sleep 1
        done

        # Wait for Wireguard interface
        until ${pkgs.iproute2}/bin/ip link show ${meshInterface} > /dev/null 2>&1; do
          echo "Waiting for ${meshInterface}..."
          sleep 1
        done

        # Create mesh network if it doesn't exist
        if ! ${pkgs.docker}/bin/docker network inspect backend > /dev/null 2>&1; then
          echo "Creating backend Docker network..."
          ${pkgs.docker}/bin/docker network create \
            --driver bridge \
            --subnet 172.20.0.0/16 \
            --opt "com.docker.network.bridge.name=br-mesh" \
            backend
        fi

        # Add nftables rules to route Docker traffic through mesh
        # Create table and chains if they don't exist
        ${pkgs.nftables}/bin/nft add table inet mesh-docker 2>/dev/null || true
        ${pkgs.nftables}/bin/nft add chain inet mesh-docker postrouting { type nat hook postrouting priority 100 \; } 2>/dev/null || true
        ${pkgs.nftables}/bin/nft add chain inet mesh-docker forward { type filter hook forward priority 0 \; } 2>/dev/null || true

        # Add NAT rule for mesh traffic
        ${pkgs.nftables}/bin/nft add rule inet mesh-docker postrouting ip saddr 172.20.0.0/16 oifname "${meshInterface}" masquerade 2>/dev/null || true

        # Add forward rules
        ${pkgs.nftables}/bin/nft add rule inet mesh-docker forward iifname "br-mesh" oifname "${meshInterface}" accept 2>/dev/null || true
        ${pkgs.nftables}/bin/nft add rule inet mesh-docker forward iifname "${meshInterface}" oifname "br-mesh" accept 2>/dev/null || true

        echo "Docker mesh network configured successfully with nftables"
      '';

      preStop = ''
        # Cleanup nftables rules
        ${pkgs.nftables}/bin/nft delete table inet mesh-docker 2>/dev/null || true
        
        # Remove network
        ${pkgs.docker}/bin/docker network rm backend 2>/dev/null || true
      '';
    };

    # Environment configuration for Docker Compose
    environment.etc."meshNetwork/docker-compose.env" = lib.mkIf cfg.dockerIntegration {
      text = ''
        # Mesh Network Configuration for Docker Compose
        MESH_NETWORK=backend
        MESH_NODE_IP=10.255.0.${toString cfg.nodeId}
        MESH_SUBNET=${meshSubnet}
      '';
      mode = "0444";
    };

    # Helper commands
    environment.systemPackages = with pkgs; [
      wireguard-tools
    ];

    # Status script
    environment.etc."meshNetwork/status.sh" = {
      text = ''
        #!/usr/bin/env bash
        echo "=== Mesh Network Status ==="
        echo
        echo "Node ID: ${toString cfg.nodeId}"
        echo "Mesh IP: 10.255.0.${toString cfg.nodeId}"
        echo
        echo "=== Wireguard Interface ==="
        ${pkgs.wireguard-tools}/bin/wg show ${meshInterface}
        echo
        echo "=== Mesh Routes ==="
        ${pkgs.iproute2}/bin/ip route show dev ${meshInterface}
        echo
        echo "=== Peer Connectivity ==="
        ${lib.concatMapStrings (peer: ''
          echo -n "Node ${toString peer.nodeId} (10.255.0.${toString peer.nodeId}): "
          ${pkgs.iputils}/bin/ping -c 1 -W 1 10.255.0.${toString peer.nodeId} > /dev/null 2>&1 && echo "✓ UP" || echo "✗ DOWN"
        '') cfg.peers}
        ${lib.optionalString cfg.dockerIntegration ''
          echo
          echo "=== Docker Mesh Network ==="
          ${pkgs.docker}/bin/docker network inspect backend 2>/dev/null | ${pkgs.jq}/bin/jq -r '.[0].Name + " (" + .[0].Driver + ")"' || echo "Not created"
        ''}
      '';
      mode = "0555";
    };
    }
    ]))
  ];
}
