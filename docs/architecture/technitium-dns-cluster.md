# Technitium DNS Cluster Architecture

**Last Updated:** 2026-01-26

**Status:** Implementation Plan

## Overview

This document describes the architecture for a Technitium DNS authoritative cluster with centralized certificate management, mesh network cluster communication, and split-horizon DNS resolution.

## Goals

1. **Centralized Certificate Management** - All ACME certificates generated on rp1
2. **Fullchain Certificates** - PKCS#12 format with complete chain for Technitium
3. **Mesh Network Clustering** - All cluster sync traffic (53443) routed through WireGuard
4. **Authoritative DNS** - Support both internal and external clients
5. **High Availability** - Two-node cluster with automatic failover

## Network Topology

### IP Addressing

| Host | Physical IP | Mesh IP | Role |
|------|-------------|---------|------|
| rp1 | 10.1.12.2/3/4 | 10.255.0.2 | Reverse Proxy, Cert Authority |
| apps1 | 10.1.11.2 | 10.255.0.3 | Primary DNS (dnsOne) |
| apps2 | 10.1.11.3 | 10.255.0.4 | Secondary DNS (dnsTwo) |

### Port Allocation

| Service | Port | Protocol | Binding | Purpose |
|---------|------|----------|---------|---------|
| DNS | 53 | TCP/UDP | Physical IP | Public DNS resolution |
| DoT | 853 | TCP | Physical IP | DNS over TLS |
| Admin Web UI | 5380 | TCP | Mesh IP | Web management interface |
| Cluster Sync | 53443 | TCP/TLS | Mesh IP | Zone replication, cluster sync |

## Certificate Distribution Architecture

### Certificate Flow

```
rp1 (ACME Generation)
    │
    ├── Let's Encrypt HTTP-01 Challenge
    │   └── Validates *.dns.reinitialized.net
    │
    ├── Certificate Processing
    │   ├── Generate fullchain.pem
    │   ├── Convert to PKCS#12 (cert.pfx)
    │   └── Store in /mnt/containers/dns-certs/
    │
    └── Distribution via Mesh
        ├── rsync over SSH to apps1 (10.255.0.3)
        │   └── /var/lib/acme/one.dns.reinitialized.net/
        │
        └── rsync over SSH to apps2 (10.255.0.4)
            └── /var/lib/acme/two.dns.reinitialized.net/
```

### Certificate Distribution Service

The distribution uses SSH over the mesh network for secure transfer:

1. **rp1** generates certificates via ACME
2. **postRun hook** triggers distribution script
3. **rsync over mesh** copies cert.pfx to each DNS node
4. **Remote reload** restarts Technitium containers

```nix
# rp1: Certificate distribution service
systemd.services.dns-cert-distribute = {
  description = "Distribute DNS certificates to cluster nodes";
  after = [ "network.target" ];
  serviceConfig = {
    Type = "oneshot";
  };
  script = ''
    # Convert and distribute one.dns certificate
    openssl pkcs12 -export -legacy \
      -out /mnt/containers/dns-certs/one.dns.pfx \
      -inkey /var/lib/acme/one.dns.reinitialized.net/key.pem \
      -in /var/lib/acme/one.dns.reinitialized.net/fullchain.pem \
      -passout pass:
    
    rsync -avz --delete \
      /mnt/containers/dns-certs/one.dns.pfx \
      rnetadmin@10.255.0.3:/var/lib/acme/one.dns.reinitialized.net/cert.pfx
    
    ssh rnetadmin@10.255.0.3 "docker restart dnsOne"
    
    # Convert and distribute two.dns certificate
    openssl pkcs12 -export -legacy \
      -out /mnt/containers/dns-certs/two.dns.pfx \
      -inkey /var/lib/acme/two.dns.reinitialized.net/key.pem \
      -in /var/lib/acme/two.dns.reinitialized.net/fullchain.pem \
      -passout pass:
    
    rsync -avz --delete \
      /mnt/containers/dns-certs/two.dns.pfx \
      rnetadmin@10.255.0.4:/var/lib/acme/two.dns.reinitialized.net/cert.pfx
    
    ssh rnetadmin@10.255.0.4 "docker restart dnsTwo"
  '';
};
```

## Technitium DNS Cluster Configuration

### Cluster Setup Requirements

1. Both nodes must be reachable via their 53443 HTTPS endpoints
2. Certificates must be fullchain (no PartialChain errors)
3. Cluster communication uses mesh IPs for security

### Technitium Settings

In the Technitium web admin (`Settings > Web Service`):

| Setting | dnsOne (apps1) | dnsTwo (apps2) |
|---------|----------------|----------------|
| Web Service Local Addresses | 10.255.0.3 | 10.255.0.4 |
| Web Service HTTP Port | 5380 | 5380 |
| Web Service HTTPS Port | 53443 | 53443 |
| TLS Certificate Path | /etc/dns/certs/cert.pfx | /etc/dns/certs/cert.pfx |
| Enable DNS over HTTPS | Yes (mesh only) | Yes (mesh only) |

### Cluster Formation

In Technitium (`Settings > General > Cluster`):

**Primary (dnsOne on apps1):**
```
Cluster Mode: Primary
Cluster Members: https://10.255.0.4:53443/
```

**Secondary (dnsTwo on apps2):**
```
Cluster Mode: Secondary  
Primary Server: https://10.255.0.3:53443/
```

## Host Configuration Changes

### rp1.nix Changes

```nix
# Remove: HTTP-01 proxy to apps1/apps2 for ACME challenges
# Add: Certificate distribution service with SSH key from secrets
# Add: Path watcher for trigger file from container
# Keep: Existing nginx proxying for web admin UI
# Keep: Existing stream proxying for DNS

# Container ACME postRun triggers host service via bind mount
security.acme.certs."one.dns.reinitialized.net" = {
  postRun = ''
    touch /run/host-trigger/distribute-certs
  '';
};

# Path watcher triggers distribution service
systemd.paths.dns-cert-distribute = {
  pathConfig.PathModified = "/run/dns-cert-trigger/distribute-certs";
  pathConfig.Unit = "dns-cert-distribute.service";
};

# Distribution service uses SSH key from secrets
systemd.services.dns-cert-distribute = {
  script = let
    sshKeyFile = config.secrets.certDistribution.file;
  in ''
    # Uses ${sshKeyFile} for SSH authentication
    # Converts certs to PKCS#12 and distributes via rsync
  '';
};
```

### apps1.nix / apps2.nix Changes

```nix
# Remove: Local ACME configuration
# Remove: Local nginx for ACME challenges  
# Remove: technitium-cert-reload service
# Add: SSH public key for rnetadmin from secrets
# Add: Firewall allowlist for mesh-only ports
# Keep: Docker container configuration

# Add rp1 cert distribution SSH key to rnetadmin
users.users.rnetadmin.openssh.authorizedKeys.keys = [
  config.secrets.certDistribution.keys.sshPublicKey
];

# Allow rnetadmin to restart docker containers
security.sudo-rs.extraRules = [{
  users = [ "rnetadmin" ];
  commands = [{
    command = "${pkgs.docker}/bin/docker restart dnsOne";
    options = [ "NOPASSWD" ];
  }];
}];

# Restrict cluster ports to mesh network
networking.firewall.allowlist = [
  { port = 5380; protocol = "tcp"; source = [ "10.255.0.0/24" ]; }
  { port = 53443; protocol = "tcp"; source = [ "10.255.0.0/24" ]; }
];

# Ensure certificate directory exists
systemd.tmpfiles.rules = [
  "d /var/lib/acme/one.dns.reinitialized.net 0750 root root -"
];

# Container mounts certificates from distribution location
virtualisation.oci-containers.containers.dnsOne = {
  # ... existing config ...
  volumes = [
    "technitium_data:/etc/dns"
    "/var/lib/acme/one.dns.reinitialized.net:/etc/dns/certs:ro"
  ];
};
```

## Security Considerations

### Mesh Network Security

- All cluster communication (53443) restricted to mesh network
- Certificate distribution via SSH over mesh (encrypted)
- Admin UI access only through rp1 reverse proxy

### Firewall Rules

**rp1:**
- Allow 53/853 inbound from internet (DNS)
- Allow 443 inbound from internet (web admin via proxy)
- Allow 80 inbound from internet (ACME HTTP-01)

**apps1/apps2:**
- Allow 53/853 inbound from local network (direct DNS)
- Allow 5380 inbound from mesh only (admin UI)
- Allow 53443 inbound from mesh only (cluster sync)
- Deny all other inbound traffic

```nix
# apps1/apps2 firewall configuration
networking.firewall = {
  allowlist = [
    {
      port = 53;
      protocol = "tcp_udp";
      source = [ "0.0.0.0/0" ];
    }
    {
      port = 853;
      protocol = "tcp_udp";
      source = [ "0.0.0.0/0" ];
    }
    {
      port = 5380;
      protocol = "tcp";
      source = [ "10.255.0.0/24" ];  # Mesh only
    }
    {
      port = 53443;
      protocol = "tcp";
      source = [ "10.255.0.0/24" ];  # Mesh only
    }
  ];
};
```

## DNS Resolution Architecture

### External Clients

```
External Client
    │
    ▼
rp1 (10.1.12.2 or 10.1.12.3)
    │ nginx stream proxy
    ▼
apps1 (10.1.11.2) or apps2 (10.1.11.3)
    │ Technitium DNS
    ▼
Response
```

### Internal Clients

```
Internal Client (10.1.x.x)
    │
    ▼
Direct to apps1 (10.1.11.2) or apps2 (10.1.11.3)
    │ Technitium DNS
    ▼
Response
```

### Split-Horizon DNS

Technitium supports split-horizon via:
1. **Access Control Lists** - Different responses based on source IP
2. **Views** - Separate zones for internal/external
3. **Conditional Forwarding** - Route internal queries differently

## Monitoring and Maintenance

### Health Checks

```bash
# Check DNS resolution
dig @10.1.11.2 reinitialized.net +short
dig @10.1.11.3 reinitialized.net +short

# Check cluster status
curl -k https://10.255.0.3:53443/api/settings/get?token=<API_TOKEN>

# Check certificate expiry
openssl s_client -connect 10.255.0.3:53443 < /dev/null 2>/dev/null | \
  openssl x509 -noout -dates
```

### Certificate Renewal

Certificates auto-renew via Let's Encrypt. The postRun hook triggers distribution:

1. ACME renews cert on rp1
2. postRun triggers `dns-cert-distribute.service`
3. New certs pushed to apps1/apps2 via rsync
4. Technitium containers restarted

## Implementation Checklist

- [x] Configure ACME certs on rp1 with postRun hooks
- [x] Create certificate distribution service on rp1
- [x] Create path watcher for trigger file
- [x] Update apps1.nix to remove local ACME
- [x] Update apps2.nix to remove local ACME  
- [x] Add sudo-rs rules for docker restart on apps1/apps2
- [x] Add firewall allowlist for mesh-only cluster ports
- [x] Configure SSH key for rp1 → apps1/apps2 mesh access (via secrets)
- [ ] Generate SSH keypair and add to secrets files
- [ ] Deploy configuration changes
- [ ] Configure Technitium cluster in web UI
- [ ] Test certificate distribution
- [ ] Test cluster replication
- [ ] Verify DNS resolution from external clients

## Deployment Steps

### Pre-Deployment

1. **Generate SSH keypair for certificate distribution**:
   ```bash
   ssh-keygen -t ed25519 -f /tmp/cert-distribution-key -N "" -C "rp1-cert-distribution"
   ```

2. **Add private key to rp1 secrets** (`modules/secrets/rp1.nix`):
   ```nix
   certDistribution = {
     description = "SSH private key for certificate distribution";
     file = /path/to/cert-distribution-key;  # Private key file
   };
   ```

3. **Add public key to apps1/apps2 secrets** (`modules/secrets/apps1.nix` and `modules/secrets/apps2.nix`):
   ```nix
   certDistribution = {
     description = "SSH public key for certificate distribution from rp1";
     keys = {
       sshPublicKey = "ssh-ed25519 AAAA... rp1-cert-distribution";  # From cert-distribution-key.pub
     };
   };
   ```

4. **Test mesh connectivity**:
   ```bash
   # From rp1
   ping 10.255.0.3  # apps1
   ping 10.255.0.4  # apps2
   ```

### Deployment Order

1. Deploy to **apps1** first:
   ```bash
   nixos-rebuild switch --flake path:.#apps1 --target-host rnetadmin@10.1.11.2
   ```

2. Deploy to **apps2**:
   ```bash
   nixos-rebuild switch --flake path:.#apps2 --target-host rnetadmin@10.1.11.3
   ```

3. Deploy to **rp1** last:
   ```bash
   nixos-rebuild switch --flake path:.#rp1 --target-host rnetadmin@10.1.12.2
   ```

### Post-Deployment

1. **Trigger initial certificate generation** (on rp1):
   ```bash
   # Force ACME renewal in the nginx container
   machinectl shell nginx /bin/bash -c "systemctl start acme-one.dns.reinitialized.net.service"
   machinectl shell nginx /bin/bash -c "systemctl start acme-two.dns.reinitialized.net.service"
   ```

2. **Verify certificate distribution**:
   ```bash
   # Check trigger watcher is running
   systemctl status dns-cert-distribute.path
   
   # Manual trigger for testing
   systemctl start dns-cert-distribute.service
   
   # Check logs
   journalctl -u dns-cert-distribute.service -f
   ```

3. **Verify certificates on DNS nodes**:
   ```bash
   # On apps1/apps2
   ls -la /var/lib/acme/*/cert.pfx
   ```

4. **Configure Technitium Cluster** via web UI:
   
   On dnsOne (https://one.dns.reinitialized.net):
   - Settings → Web Service → TLS Certificate → Select `/etc/dns/certs/cert.pfx`
   - Settings → General → Enable Clustering
   - Set as Primary, add `https://10.255.0.4:53443/` as cluster member
   
   On dnsTwo (https://two.dns.reinitialized.net):
   - Settings → Web Service → TLS Certificate → Select `/etc/dns/certs/cert.pfx`
   - Settings → General → Enable Clustering
   - Set as Secondary, set `https://10.255.0.3:53443/` as primary

5. **Verify cluster health**:
   ```bash
   # Check cluster sync via API
   curl -k "https://10.255.0.3:53443/api/settings/getStats?token=<API_TOKEN>"
   ```

## References

- [Technitium DNS Documentation](https://technitium.com/dns/)
- [Technitium Cluster Setup](https://blog.technitium.com/2022/06/technitium-dns-server-v90-released.html)
- [Mesh Network Module](../modules/meshNetwork.md)
- [ACME/Let's Encrypt](https://nixos.wiki/wiki/ACME)
