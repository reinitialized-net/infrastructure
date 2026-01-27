# Mesh Network Module

**Module Path:** `modules/profiles/meshNetwork/`

**Import:** Automatically included with `nixosModules.default`

## Overview

Provides WireGuard-based mesh networking for NixOS systems, specifically designed for Docker container networks. Creates a secure, encrypted overlay network between multiple hosts, allowing containers to communicate across physical machines.

## Features

- **WireGuard VPN**: Secure, fast, modern VPN technology
- **Mesh Topology**: All nodes can communicate directly
- **Docker Integration**: Automatic Docker network configuration
- **nftables NAT**: Routing and NAT for container traffic
- **Auto-configuration**: Integrates with secrets module
- **Helper Tools**: Status monitoring and key generation utilities
- **Persistent Connections**: Automatic keepalive configuration

## Option: `services.meshNetwork`

### Configuration Options

#### `enable`

**Type:** `bool`

**Default:** `false`

**Description:** Enable the WireGuard mesh network.

```nix
services.meshNetwork.enable = true;
```

#### `nodeId`

**Type:** `int` (1-254)

**Required:** Yes (unless set via secrets)

**Description:** Unique node identifier for this mesh member. Used to calculate the mesh IP address (`10.255.0.<nodeId>`).

**Auto-configuration:** Can be sourced from `secrets.meshNetwork.keys.nodeId`

```nix
services.meshNetwork.nodeId = 1;
# Results in mesh IP: 10.255.0.1
```

#### `listenPort`

**Type:** `port`

**Default:** `51820`

**Description:** UDP port for WireGuard to listen on.

**Auto-configuration:** Can be sourced from `secrets.meshNetwork.keys.listenPort`

```nix
services.meshNetwork.listenPort = 51820;
```

#### Private Key Configuration

**Note:** The mesh network module automatically sources the WireGuard private key from `secrets.meshNetwork.file`. There is no separate `privateKeyFile` option - configure your private key via the secrets module:

```nix
# In modules/secrets/<hostname>.nix
secrets.meshNetwork = {
  description = "MeshNetwork secrets";
  file = lib.mkDefault (builtins.toFile "mesh-privatekey" "YOUR_PRIVATE_KEY_HERE");
};
```

#### `peers`

**Type:** `listOf (submodule)`

**Default:** `[]`

**Description:** List of other mesh network nodes to connect to. If empty and `autoPeers` is enabled, peers will be automatically populated from the centralized topology in `meshTopology.nix`.

**Auto-configuration:** 
- Can be sourced from `secrets.meshNetwork.keys.peers`
- Can be automatically populated from `meshTopology.nix` when `autoPeers = true`

**Peer Options:**

- **`nodeId`** (int, required): Node ID of the peer (1-254)
- **`publicKey`** (string, required): WireGuard public key of the peer
- **`endpoint`** (string, optional): Connection endpoint as `IP:PORT`. At least one node must have an endpoint for NAT traversal. Set to `null` for nodes behind NAT.
- **`persistentKeepalive`** (int, optional, default: 25): Keepalive interval in seconds. Set to `null` to disable.

```nix
# Manual peer configuration (autoPeers = false)
services.meshNetwork.peers = [
  {
    nodeId = 2;
    publicKey = "peer2_public_key_here";
    endpoint = "192.168.1.100:51820";
    persistentKeepalive = 25;
  }
  {
    nodeId = 3;
    publicKey = "peer3_public_key_here";
    endpoint = null;  # Behind NAT, will connect to others
    persistentKeepalive = 25;
  }
];
```

#### `autoPeers`

**Type:** `bool`

**Default:** `true`

**Description:** Automatically populate peers from the centralized topology defined in `meshTopology.nix`. When enabled and `peers` is empty, the module will automatically fetch all other nodes from the topology based on this node's `nodeId`.

This eliminates the need to manually configure peers on each node - you only need to maintain the topology in one place.

```nix
# Enable automatic peer population (default)
services.meshNetwork.autoPeers = true;

# Disable to use manual peer configuration
services.meshNetwork.autoPeers = false;
```

**Note:** When `autoPeers = true` and `peers` is not empty, the manual peer list will be used instead.

#### `dockerIntegration`

**Type:** `bool`

**Default:** `true`

**Description:** Enable automatic Docker network configuration and routing through the mesh.

```nix
services.meshNetwork.dockerIntegration = true;
```

## Quick Start

### Using Centralized Topology (Recommended)

The easiest way to configure the mesh network is to use the centralized topology in `meshTopology.nix`. This approach eliminates duplication and automatically configures all peers.

**Key Feature:** With `autoPeers = true` (default), you only need to set your `nodeId` - the module automatically discovers all other peers from the centralized topology.

#### 1. Generate Keys

On each node:

```bash
# Generate key pair
wg genkey | tee privatekey | wg pubkey > publickey

# View keys
cat privatekey  # Keep this secret!
cat publickey   # Share with other nodes
```

#### 2. Add Node to Topology

Edit `modules/profiles/meshNetwork/meshTopology.nix`:

```nix
nodes = {
  devenv = {
    nodeId = 1;
    hostname = "devenv";
    endpoint = "10.1.200.2:51820";
    publicKey = "zKEWyw9tClll136BGRSv2ImwiP6wNpeJ8ZqG6+ETnmY=";
  };
  
  rp1 = {
    nodeId = 2;
    hostname = "rp1";
    endpoint = "10.1.12.2:51820";
    publicKey = "RCmhMTQbaHCwfYeJYOF0J09aGdZvAWDuIakUY3tomGk=";
  };
  
  # Add your new node here
  mynewnode = {
    nodeId = 3;
    hostname = "mynewnode";
    endpoint = "10.1.11.5:51820";  # or null if behind NAT
    publicKey = "YOUR_PUBLIC_KEY_HERE";
  };
};
```

#### 3. Configure Secrets

Create `modules/secrets/<hostname>.nix` with your private key:

```nix
{
  lib,
  ...
}: {
  secrets = {
    meshNetwork = {
      description = "MeshNetwork secrets";
      file = lib.mkDefault (builtins.toFile "mesh-privatekey" "YOUR_PRIVATE_KEY_HERE");
    };
  };
}
```

#### 4. Enable in Host Configuration

In `hosts/<hostname>.nix`:

```nix
services.meshNetwork = {
  enable = true;
  nodeId = 3;  # Must match the nodeId in meshTopology.nix
  # Peers are automatically populated from topology!
};
```

That's it! The module will automatically configure all peers from the topology.

### Manual Configuration (Legacy)

If you prefer to manually configure peers or need custom configuration:

#### 1. Generate Keys

On each node:

```bash
# Generate key pair
wg genkey | tee privatekey | wg pubkey > publickey

# View keys
cat privatekey  # Keep this secret!
cat publickey   # Share with other nodes
```

#### 2. Configure Secrets

Create `modules/secrets/mesh.nix`:

```nix
{
  secrets.meshNetwork = {
    description = "Mesh network configuration";
    
    # Private key as file
    file = builtins.toFile "mesh-privatekey" "your_private_key_here";
    
    keys = {
      nodeId = 1;
      listenPort = 51820;
      
      peers = [
        {
          nodeId = 2;
          publicKey = "peer2_public_key";
          endpoint = "192.168.1.100:51820";
          persistentKeepalive = 25;
        }
        {
          nodeId = 3;
          publicKey = "peer3_public_key";
          endpoint = "192.168.1.101:51820";
          persistentKeepalive = 25;
        }
      ];
    };
  };
}
```

#### 3. Enable the Module

In your configuration:

```nix
{
  imports = [ ./modules/secrets/mesh.nix ];
  
  # Enable mesh network with manual peer configuration
  services.meshNetwork = {
    enable = true;
    autoPeers = false;  # Disable automatic peer population
  };
  
  # Configuration is auto-loaded from secrets
  # nodeId must be set in host config or secrets
}
```

## Centralized Topology

### Overview

The `meshTopology.nix` file provides a centralized place to define all mesh network nodes. This eliminates the need to configure peers on every node individually.

**File Location:** `modules/profiles/meshNetwork/meshTopology.nix`

### Structure

```nix
{ lib }: let
  meshSubnet = "10.255.0.0/24";
  
  nodes = {
    <hostname> = {
      nodeId = <unique-id>;
      hostname = "<hostname>";
      endpoint = "<ip>:<port>";  # or null
      publicKey = "<wireguard-public-key>";
    };
    # ... more nodes
  };
in {
  inherit meshSubnet nodes;
  
  # Utility functions
  getPeersForNode = nodeId: /* ... */;
  getNodeByNodeId = nodeId: /* ... */;
  getNodeByHostname = hostname: /* ... */;
}
```

### Available Functions

#### `getPeersForNode`

Returns a list of all peers for a given nodeId, automatically excluding the node itself.

```nix
# Returns: [ { nodeId = 2; publicKey = "..."; endpoint = "..."; persistentKeepalive = 25; } ... ]
meshTopology.getPeersForNode 1
```

This is the function used by the `autoPeers` feature to automatically populate peer configurations.

#### `getNodeByNodeId`

Look up a node's configuration by its nodeId.

```nix
# Returns: { nodeId = 1; hostname = "devenv"; endpoint = "..."; publicKey = "..."; }
meshTopology.getNodeByNodeId 1
```

#### `getNodeByHostname`

Look up a node's configuration by its hostname.

```nix
# Returns: { nodeId = 1; hostname = "devenv"; endpoint = "..."; publicKey = "..."; }
meshTopology.getNodeByHostname "devenv"
```

### Adding a New Node

1. Generate WireGuard keys on the new node
2. Add entry to `meshTopology.nix`:

```nix
nodes = {
  # ... existing nodes ...
  
  newnode = {
    nodeId = 4;  # Must be unique
    hostname = "newnode";
    endpoint = "10.1.11.10:51820";
    publicKey = "NEW_NODE_PUBLIC_KEY";
  };
};
```

3. Create secrets file for the new node: `modules/secrets/newnode.nix`
4. Enable mesh network in the host config with just `nodeId` - peers auto-populate!

All existing nodes will automatically include the new node in their peer list on next rebuild.

### 4. Build and Deploy

```bash
# Build the configuration
nixos-rebuild build --flake path:.#hostname

# Deploy
nixos-rebuild switch --flake path:.#hostname
```

## Complete Examples

### Two-Node Mesh

**Node 1 (Public IP: 203.0.113.10)**

```nix
# modules/secrets/node1.nix
{
  secrets.meshNetwork = {
    description = "Node 1 mesh credentials";
    file = lib.mkDefault (builtins.toFile "mesh-privatekey" "node1_private_key_here");
  };
}

# hosts/node1.nix
{
  services.meshNetwork = {
    enable = true;
    nodeId = 1;
    autoPeers = false;  # Manual peer configuration
    
    peers = [
      {
        nodeId = 2;
        publicKey = "node2_public_key";
        endpoint = "203.0.113.20:51820";
      }
    ];
  };
}
```

**Node 2 (Public IP: 203.0.113.20)**

```nix
# modules/secrets/node2.nix
{
  secrets.meshNetwork = {
    description = "Node 2 mesh credentials";
    file = lib.mkDefault (builtins.toFile "mesh-privatekey" "node2_private_key_here");
  };
}

# hosts/node2.nix
{
  services.meshNetwork = {
    enable = true;
    nodeId = 2;
    autoPeers = false;  # Manual peer configuration
    
    peers = [
      {
        nodeId = 1;
        publicKey = "node1_public_key";
        endpoint = "203.0.113.10:51820";
      }
    ];
  };
}
```

### Three-Node Mesh (Hub-and-Spoke)

**Hub (Node 1 - Public IP)**

```nix
# modules/secrets/hub.nix
{
  secrets.meshNetwork.file = lib.mkDefault (builtins.toFile "mesh-privatekey" "hub_private_key");
}

# hosts/hub.nix
{
  services.meshNetwork = {
    enable = true;
    nodeId = 1;
    autoPeers = false;
    
    peers = [
      {
        nodeId = 2;
        publicKey = "node2_public_key";
        endpoint = null;  # Spoke will connect to us
      }
      {
        nodeId = 3;
        publicKey = "node3_public_key";
        endpoint = null;  # Spoke will connect to us
      }
    ];
  };
}
```

**Spoke Nodes (Behind NAT)**

```nix
# modules/secrets/spoke.nix
{
  secrets.meshNetwork.file = lib.mkDefault (builtins.toFile "mesh-privatekey" "spoke_private_key");
}

# hosts/spoke.nix
{
  services.meshNetwork = {
    enable = true;
    nodeId = 2;  # or 3 for the other spoke
    autoPeers = false;
    
    peers = [
      {
        nodeId = 1;
        publicKey = "hub_public_key";
        endpoint = "203.0.113.10:51820";  # Hub's public IP
        persistentKeepalive = 25;  # Keep NAT hole open
      }
    ];
  };
}
```

### Mesh with Docker

```nix
{
  # Private key configured via secrets.meshNetwork.file
  
  # Enable Docker
  virtualisation.docker.enable = true;
  
  # Enable mesh network (uses autoPeers from meshTopology.nix)
  services.meshNetwork = {
    enable = true;
    nodeId = 1;
    dockerIntegration = true;
  };
  
  # Containers can now use the 'backend' network
  virtualisation.oci-containers.containers.myapp = {
    image = "nginx:latest";
    extraOptions = [ "--network=backend" ];
  };
}
```

## Docker Integration

When `dockerIntegration = true`, the module automatically:

1. **Creates Docker Network**: `backend` bridge network (172.20.0.0/16)
2. **Configures Routing**: Routes container traffic through mesh
3. **Sets Up NAT**: nftables rules for masquerading
4. **Provides Environment File**: `/etc/meshNetwork/docker-compose.env`

### Using in Docker Compose

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  app:
    image: myapp:latest
    networks:
      - backend
    environment:
      # Other containers on the mesh
      - DATABASE_HOST=10.255.0.2
      - REDIS_HOST=10.255.0.3

networks:
  backend:
    external: true  # Uses the mesh network
```

Deploy:

```bash
docker-compose up -d
```

### Environment Variables

The module creates `/etc/meshNetwork/docker-compose.env`:

```bash
MESH_NETWORK=backend
MESH_NODE_IP=10.255.0.1
MESH_SUBNET=10.255.0.0/24
```

Source in compose files:

```yaml
services:
  app:
    env_file:
      - /etc/meshNetwork/docker-compose.env
```

## Helper Tools

The module provides command-line utilities (when mesh is enabled):

### `mesh-keygen`

Generate a new WireGuard key pair:

```bash
mesh-keygen

# Output:
# === Wireguard Mesh Key Generator ===
# 
# Private Key: aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567890ABCD=
# Public Key:  XyZ1234567890ABCDeFgHiJkLmNoPqRsTuVwXyZabc=
# 
# ⚠️  IMPORTANT: Store the private key securely!
#    Add the private key to: modules/secrets/mesh.nix
#    Share the public key with other mesh nodes
```

### `mesh-status`

Show current mesh network status:

```bash
mesh-status

# Output:
# === Mesh Network Status ===
# 
# Node ID: 1
# Mesh IP: 10.255.0.1
# 
# === Wireguard Interface ===
# interface: wg-mesh
#   public key: abc123...
#   private key: (hidden)
#   listening port: 51820
# 
# peer: xyz789...
#   endpoint: 192.168.1.100:51820
#   allowed ips: 10.255.0.2/32
#   latest handshake: 30 seconds ago
#   transfer: 1.2 GiB received, 856 MiB sent
# 
# === Mesh Routes ===
# 10.255.0.0/24 dev wg-mesh scope link
# 
# === Peer Connectivity ===
# Node 2 (10.255.0.2): ✓ UP
# Node 3 (10.255.0.3): ✗ DOWN
# 
# === Docker Mesh Network ===
# backend (bridge)
```

### `mesh-test`

Test connectivity to all mesh peers:

```bash
mesh-test

# Output:
# === Mesh Network Connectivity Test ===
# 
# Testing 10.255.0.2 ... ✓ OK (12.3ms)
# Testing 10.255.0.3 ... ✗ FAILED
# 
# === Bandwidth Test (iperf3) ===
# To test bandwidth between nodes:
#   On receiver: iperf3 -s
#   On sender:   iperf3 -c <mesh-ip>
```

## Network Architecture

### IP Addressing

- **Mesh Network**: `10.255.0.0/24`
- **Node IPs**: `10.255.0.<nodeId>`
- **Docker Network**: `172.20.0.0/16`

### Network Flow

```
Container (172.20.0.x)
    ↓
Docker Bridge (br-mesh)
    ↓
NAT / Routing
    ↓
WireGuard (wg-mesh) - 10.255.0.x
    ↓
Internet / LAN
    ↓
Remote WireGuard (wg-mesh) - 10.255.0.y
    ↓
NAT / Routing
    ↓
Docker Bridge (br-mesh)
    ↓
Remote Container (172.20.0.y)
```

### Firewall Rules

Automatically configured:

- **Peer IP Allowlist**: WireGuard port (51820) is automatically restricted to declared peer endpoints only using `networking.firewall.allowlist`
- **Trusted Interface**: `wg-mesh` marked as trusted
- **nftables NAT**: Masquerading for Docker traffic

**Security Note:** The module automatically extracts peer endpoint IP addresses from the mesh topology and configures firewall rules to only allow WireGuard traffic from those specific IPs. This ensures that only declared mesh peers can establish connections, providing an additional layer of security beyond WireGuard's cryptographic authentication.

## Troubleshooting

### Check WireGuard Status

```bash
wg show wg-mesh
```

### Check Routes

```bash
ip route show dev wg-mesh
```

### Verify Docker Network

```bash
docker network inspect backend
```

### Check nftables Rules

```bash
nft list table inet mesh-docker
```

### Test Connectivity

```bash
# Ping peer
ping 10.255.0.2

# Check from container
docker run --rm --network backend alpine ping 10.255.0.2
```

### Common Issues

**1. Handshake not completing**
- Check endpoints are correct
- Verify UDP port 51820 is open
- Check firewall rules on both sides

**2. Can't reach peers**
- Verify public keys are correct
- Check `persistentKeepalive` is set for NAT traversal
- Ensure routes are present: `ip route show`

**3. Docker containers can't reach mesh**
- Verify `dockerIntegration = true`
- Check Docker network exists: `docker network ls`
- Verify nftables rules: `nft list ruleset`

**4. Private key errors**
- Ensure private key file has correct permissions
- Verify file path is correct
- Check key is valid: `wg pubkey < /path/to/privatekey`

## Security Considerations

1. **Private Keys**: Store securely, never commit to git
2. **Endpoints**: Use DNS names for dynamic IPs
3. **Firewall**: Mesh interface is trusted - secure physical hosts. WireGuard port is automatically allowlisted to only accept connections from declared peer endpoints.
4. **NAT**: Docker traffic is masqueraded, plan IP ranges carefully
5. **Peer Authentication**: Two-layer security - IP allowlisting at firewall level plus WireGuard's cryptographic authentication

## Integration with Secrets Module

Recommended setup using secrets:

```nix
{
  # Define secrets
  secrets.meshNetwork = {
    description = "Mesh network credentials";
    file = /run/secrets/mesh-privatekey;
    keys = {
      nodeId = 1;
      listenPort = 51820;
      peers = [ /* ... */ ];
    };
  };
  
  # Enable mesh (auto-configures from secrets)
  services.meshNetwork.enable = true;
}
```

Benefits:
- Centralized secret management
- Easy to override for testing
- Self-documenting configuration

## See Also

- [Secrets Module](secrets.md) - Managing mesh credentials
- [Containers Profile](containers.md) - Docker configuration
- [Firewall Module](firewall.md) - Firewall rules
- [Examples](../examples.md) - Complete configurations
