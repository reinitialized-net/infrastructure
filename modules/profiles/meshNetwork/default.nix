{
  self,
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.services.meshNetwork;
  meshInterface = "wg-mesh";
  
  # Import centralized topology
  meshTopology = import ./meshTopology.nix { inherit lib; };
  meshSubnet = meshTopology.meshSubnet;
  
  # Check if secrets.meshNetwork is configured
  hasSecrets = config.secrets ? meshNetwork;
  secretsCfg = if hasSecrets then config.secrets.meshNetwork else {};

  # Utility functions for subnet parsing
  meshLib = {
    # Extract the network prefix from a CIDR subnet (e.g., "10.255.0.0/24" -> "10.255.0")
    getSubnetPrefix = subnet: let
      # Split on "/" to get IP part
      ipPart = lib.head (lib.splitString "/" subnet);
      # Split IP into octets
      octets = lib.splitString "." ipPart;
      # Take first 3 octets and rejoin
      prefix = lib.concatStringsSep "." (lib.take 3 octets);
    in prefix;
    
    # Generate allowedIPs for a peer based on subnet and peer node ID
    # e.g., subnet="10.255.0.0/24", nodeId=5 -> "10.255.0.5/32"
    getPeerAllowedIP = subnet: nodeId: let
      prefix = meshLib.getSubnetPrefix subnet;
    in "${prefix}.${toString nodeId}/32";
  };
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
        If empty and nodeId is set, peers will be automatically generated from meshTopology.
        Can be automatically sourced from secrets.meshNetwork.keys.peers if configured.
      '';
    };

    autoPeers = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Automatically populate peers from meshTopology.nix based on nodeId.
        Set to false to manually configure peers via the peers option.
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

      networking.wireguard.interfaces.${meshInterface} = let
        # Determine final peer list: use autoPeers if enabled and peers is empty, otherwise use configured peers
        finalPeers = if cfg.autoPeers && cfg.peers == []
                     then meshTopology.getPeersForNode cfg.nodeId
                     else cfg.peers;
      in {
        ips = [ (meshLib.getPeerAllowedIP meshSubnet cfg.nodeId) ];
        listenPort = cfg.listenPort;
        privateKeyFile = secretsCfg.file;

        peers = builtins.map (peer: {
          publicKey = peer.publicKey;
          allowedIPs = [ (meshLib.getPeerAllowedIP meshSubnet peer.nodeId) ];
          endpoint = lib.mkIf (peer.endpoint != null) peer.endpoint;
          persistentKeepalive = lib.mkIf (peer.persistentKeepalive != null) peer.persistentKeepalive;
        }) finalPeers;
      };

    # Configure WireGuard interface with networkd for routing
    systemd.network.networks."50-${meshInterface}" = {
      matchConfig.Name = meshInterface;
      networkConfig = {
        Address = (meshLib.getPeerAllowedIP meshSubnet cfg.nodeId);
      };
      routes = [
        {
          Destination = meshSubnet;
          Scope = "link";
        }
      ];
    };

    # Docker integration
    virtualisation.docker = lib.mkIf (cfg.dockerIntegration && config.virtualisation.docker.enable) {
      daemon.settings = {
        # Add mesh network to Docker daemon
        bip = lib.mkDefault "172.17.0.1/16";
        fixed-cidr = lib.mkDefault "172.17.0.0/16";
      };
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
        MESH_NODE_IP=${meshLib.getSubnetPrefix meshSubnet}.${toString cfg.nodeId}
        MESH_SUBNET=${meshSubnet}
      '';
      mode = "0444";
    };

    # Add required packages
    environment.systemPackages = with pkgs; [
      wireguard-tools
      iproute2
      iputils
      jq
    ];

    # Status script
    environment.etc."meshNetwork/status.sh" = {
      text = ''
        #!/usr/bin/env bash
        echo "=== Mesh Network Status ==="
        echo
        echo "Node ID: ${toString cfg.nodeId}"
        echo "Mesh IP: ${meshLib.getSubnetPrefix meshSubnet}.${toString cfg.nodeId}"
        echo
        echo "=== Wireguard Interface ==="
        sudo ${pkgs.wireguard-tools}/bin/wg show ${meshInterface}
        echo
        echo "=== Mesh Routes ==="
        ${pkgs.iproute2}/bin/ip route show dev ${meshInterface}
        echo
        echo "=== Peer Connectivity ==="
        ${lib.concatMapStrings (peer: ''
          echo -n "Node ${toString peer.nodeId} (${meshLib.getSubnetPrefix meshSubnet}.${toString peer.nodeId}): "
          ${pkgs.iputils}/bin/ping -c 1 -W 1 ${meshLib.getSubnetPrefix meshSubnet}.${toString peer.nodeId} > /dev/null 2>&1 && echo "✓ UP" || echo "✗ DOWN"
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
