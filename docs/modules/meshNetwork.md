# Mesh Network Module

**Module path:** `modules/profiles/meshNetwork/`

**Primary option:** `services.meshNetwork`

## Overview

The mesh network module configures a WireGuard interface named `wg-mesh` and can create a Docker bridge network named `backend` for containers that need to reach services on other hosts.

The centralized topology lives in `modules/profiles/meshNetwork/meshTopology.nix`. Public keys belong there. Private keys belong in each host's live secret file as `secrets.meshNetwork.file`.

## Options

| Option | Type | Default | Notes |
|--------|------|---------|-------|
| `enable` | bool | `false` | Enables WireGuard mesh configuration |
| `nodeId` | int | Looks up `networking.hostName` in `meshTopology.nix` | Used for `10.255.0.<nodeId>` |
| `listenPort` | port | `51820` | UDP listen port |
| `peers` | list | `[]` | Manual peers; used when non-empty or `autoPeers = false` |
| `autoPeers` | bool | `true` | When true and `peers` is empty, peers come from topology |
| `dockerIntegration` | bool | `true` | Creates Docker `backend` network only when Docker is enabled |

Peer entries contain:

| Peer option | Required | Notes |
|-------------|----------|-------|
| `nodeId` | Yes | Peer node ID |
| `publicKey` | Yes | WireGuard public key |
| `endpoint` | No | `IP:PORT`, or `null` |
| `persistentKeepalive` | No | Defaults to `25`; set to `null` to omit |

The module reads the private key from:

```nix
config.secrets.meshNetwork.file
```

It does not read `nodeId`, `listenPort`, or `peers` from `secrets.meshNetwork.keys`.

## Current Topology

| Host | Node ID | Mesh IP | Endpoint |
|------|---------|---------|----------|
| `devenv` | 1 | `10.255.0.1` | `10.1.200.2:51820` |
| `rp1` | 2 | `10.255.0.2` | `10.1.12.2:51820` |
| `apps1` | 3 | `10.255.0.3` | `10.1.11.2:51820` |
| `apps2` | 4 | `10.255.0.4` | `10.1.11.3:51820` |
| `apps3` | 5 | `10.255.0.5` | `10.1.11.4:51820` |
| `gs1` | 6 | `10.255.0.6` | `10.1.11.6:51820` |
| `ai1` | 9 | `10.255.0.9` | `10.1.11.9:51820` |
| `db1` | 11 | `10.255.0.11` | `10.1.11.11:51820` |

`gs1` is in topology but not currently exported from `flake.nix`.

## Minimal Host Configuration

For a host already present in `meshTopology.nix`, set the hostname and enable the service:

```nix
{
  networking.hostName = "apps1";

  services.meshNetwork = {
    enable = true;
    # nodeId defaults from meshTopology.nix
    # peers default from meshTopology.nix
  };
}
```

Create the private key secret in `modules/secrets/<host>.nix`:

```nix
{
  lib,
  ...
}: {
  secrets.meshNetwork = {
    description = "MeshNetwork WireGuard private key";
    file = lib.mkDefault (builtins.toFile "mesh-privatekey" "PLACE PRIVATE KEY HERE");
  };
}
```

## Adding A Node

1. Generate a key pair on a trusted machine:

   ```bash
   mesh-keygen
   ```

   or:

   ```bash
   wg genkey | tee privatekey | wg pubkey > publickey
   ```

2. Add the public key and endpoint to `modules/profiles/meshNetwork/meshTopology.nix`.

3. Add the host configuration in `hosts/<host>.nix`.

4. Add a matching secret template in `modules/secrets.example/<host>.nix`.

5. Export the host in `flake.nix` with `makeDualExport` if it should build as `.#<host>`.

6. Build at least the new host:

   ```bash
   nix build path:.#nixosConfigurations.<host>.config.system.build.toplevel
   ```

When an existing host is rebuilt, `autoPeers = true` causes it to include the new topology peer automatically.

## Firewall Behavior

When enabled, the module:

- trusts the `wg-mesh` interface through `networking.firewall.trustedInterfaces`
- adds a UDP allowlist rule for the WireGuard listen port from peer endpoint IPs when endpoints are known

The allowlist rule is generated from the final peer list. Peers with `endpoint = null` do not contribute source IPs to that rule.

## Docker Integration

When `dockerIntegration = true` and Docker is enabled, the module creates:

- Docker bridge network `backend`
- bridge name `br-mesh`
- Docker subnet `172.20.0.0/16`
- nftables NAT and forward rules for traffic between `br-mesh` and `wg-mesh`
- `/etc/meshNetwork/docker-compose.env`

The environment file contains:

```bash
MESH_NETWORK=backend
MESH_NODE_IP=10.255.0.<nodeId>
MESH_SUBNET=10.255.0.0/24
```

Declarative OCI containers in this repository use:

```nix
networks = [ "backend" ];
```

## Helper Tools

These tools are installed only when `services.meshNetwork.enable = true`:

| Tool | Purpose |
|------|---------|
| `mesh-keygen` | Generate a WireGuard private/public key pair |
| `mesh-status` | Run `/etc/meshNetwork/status.sh` if the host generated one |
| `mesh-test` | Ping every peer IP from `wg show wg-mesh` allowed IPs |

`mesh-status` depends on the generated `/etc/meshNetwork/status.sh`. That generated script prints WireGuard status, routes, peer pings, and Docker network status when Docker integration is enabled.

## Troubleshooting

Check the interface:

```bash
ip addr show wg-mesh
sudo wg show wg-mesh
```

Test peer connectivity:

```bash
mesh-test
```

Inspect Docker mesh networking:

```bash
docker network inspect backend
nft list table inet mesh-docker
```

Common causes of failure:

- `networking.hostName` is not present in `meshTopology.nix` and `services.meshNetwork.nodeId` was not set explicitly.
- `secrets.meshNetwork.file` is missing or points at a file unavailable on the target.
- The public key in topology does not match the private key in the host secret.
- A topology node was added but not exported in `flake.nix`, so `rebuildHost <host>` cannot build it.

## See Also

- [Secrets Management](secrets.md)
- [Firewall Allowlist/Denylist](firewall.md)
- [Containers Profile](containers.md)
- [Mesh Network Port Reference](../mesh-network-ports.md)
