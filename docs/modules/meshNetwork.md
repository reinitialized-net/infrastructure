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

#### `privateKeyFile`

**Type:** `path`

**Required:** Yes (unless set via secrets)

**Description:** Path to the WireGuard private key file. Generate with `wg genkey`.

**Auto-configuration:** Can be sourced from `secrets.meshNetwork.file`

```nix
services.meshNetwork.privateKeyFile = /run/secrets/mesh-privatekey;
```

#### `peers`

**Type:** `listOf (submodule)`

**Default:** `[]`

**Description:** List of other mesh network nodes to connect to.

**Auto-configuration:** Can be sourced from `secrets.meshNetwork.keys.peers`

**Peer Options:**

- **`nodeId`** (int, required): Node ID of the peer (1-254)
- **`publicKey`** (string, required): WireGuard public key of the peer
- **`endpoint`** (string, optional): Connection endpoint as `IP:PORT`. At least one node must have an endpoint for NAT traversal. Set to `null` for nodes behind NAT.
- **`persistentKeepalive`** (int, optional, default: 25): Keepalive interval in seconds. Set to `null` to disable.

```nix
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

#### `dockerIntegration`

**Type:** `bool`

**Default:** `true`

**Description:** Enable automatic Docker network configuration and routing through the mesh.

```nix
services.meshNetwork.dockerIntegration = true;
```

## Quick Start

### 1. Generate Keys

On each node:

```bash
# Generate key pair
wg genkey | tee privatekey | wg pubkey > publickey

# View keys
cat privatekey  # Keep this secret!
cat publickey   # Share with other nodes
```

### 2. Configure Secrets

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

### 3. Enable the Module

In your configuration:

```nix
{
  imports = [ ./modules/secrets/mesh.nix ];
  
  # Enable mesh network
  services.meshNetwork.enable = true;
  
  # Configuration is auto-loaded from secrets
  # Or override manually:
  # services.meshNetwork.nodeId = 1;
  # services.meshNetwork.privateKeyFile = /path/to/key;
}
```

### 4. Build and Deploy

```bash
# Build the configuration
nixos-rebuild build --flake .#hostname

# Deploy
nixos-rebuild switch --flake .#hostname
```

## Complete Examples

### Two-Node Mesh

**Node 1 (Public IP: 203.0.113.10)**

```nix
{
  services.meshNetwork = {
    enable = true;
    nodeId = 1;
    privateKeyFile = /run/secrets/wg-key-node1;
    
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
{
  services.meshNetwork = {
    enable = true;
    nodeId = 2;
    privateKeyFile = /run/secrets/wg-key-node2;
    
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
{
  services.meshNetwork = {
    enable = true;
    nodeId = 1;
    privateKeyFile = /run/secrets/wg-hub;
    
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
{
  services.meshNetwork = {
    enable = true;
    nodeId = 2;  # or 3 for the other spoke
    privateKeyFile = /run/secrets/wg-spoke;
    
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
  # Enable Docker
  virtualisation.docker.enable = true;
  
  # Enable mesh network
  services.meshNetwork = {
    enable = true;
    nodeId = 1;
    dockerIntegration = true;
    
    privateKeyFile = /run/secrets/wg-key;
    peers = [ /* ... */ ];
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

- **Allow UDP**: Port 51820 (or custom `listenPort`)
- **Trusted Interface**: `wg-mesh` marked as trusted
- **nftables NAT**: Masquerading for Docker traffic

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
3. **Firewall**: Mesh interface is trusted - secure physical hosts
4. **NAT**: Docker traffic is masqueraded, plan IP ranges carefully

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
