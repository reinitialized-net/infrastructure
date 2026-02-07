# Port Mapping Scheme Migration

**Date:** 2026-02-07  
**Status:** Complete

## Overview

Migrated from one-to-one port mapping to incremental port scheme starting at 1024 for all mesh network services.

## Rationale

The new incremental scheme simplifies port management by:
- Starting all mesh network services at port 1024
- Incrementing ports sequentially for each service
- Avoiding port conflicts
- Making port allocation more predictable

## Changes Summary

### apps1 (10.255.0.3) Port Mappings

| Service | Old Port | New Port | Internal Port | Notes |
|---------|----------|----------|---------------|-------|
| hudu_postgres1 | 5432 | 1024 | 5432 | PostgreSQL database |
| hudu1 | 3000 | 1025 | 3000 | Hudu web interface |
| dnsOne (Admin UI) | 5380 | 1026 | 5380 | Technitium web UI |
| dnsOne (Cluster) | 53443 | 1027 | 53443 | Technitium cluster sync |
| dnsOne (DNS TCP) | 53 | 1028 | 53 | DNS service |
| dnsOne (DNS UDP) | 53 | 1029 | 53 | DNS service |
| stalwartOne (HTTP) | 8080 | 1030 | 8080 | Mail web interface |
| stalwartOne (SMTP) | 25 | 1031 | 25 | Mail SMTP |
| stalwartOne (IMAP) | 143 | 1032 | 143 | Mail IMAP |
| stalwartOne (SMTPS) | 465 | 1033 | 465 | Mail SMTP over SSL |
| stalwartOne (Submission) | 587 | 1034 | 587 | Mail submission |
| stalwartOne (IMAPS) | 993 | 1035 | 993 | Mail IMAP over SSL |
| stalwartOne (POP3S) | 995 | 1036 | 995 | Mail POP3 over SSL |
| stalwartOne (Sieve) | 4190 | 1037 | 4190 | Mail Sieve |

### apps2 (10.255.0.4) Port Mappings

| Service | Old Port | New Port | Internal Port | Notes |
|---------|----------|----------|---------------|-------|
| dnsTwo (Admin UI) | 5380 | 1024 | 5380 | Technitium web UI |
| dnsTwo (Cluster) | 53443 | 1025 | 53443 | Technitium cluster sync |
| dnsTwo (DNS TCP) | 53 | 1026 | 53 | DNS service |
| dnsTwo (DNS UDP) | 53 | 1027 | 53 | DNS service |
| unifi (Web) | 8443 | 1028 | 8443 | UniFi web admin |
| unifi (STUN) | 3478 | 1029 | 3478 | UniFi STUN |
| unifi (Discovery) | 10001 | 1030 | 10001 | UniFi device discovery |
| unifi (Communication) | 8080 | 1031 | 8080 | UniFi device comm |
| pgadmin4 | 80 (wrong host) | 1032 | 80 | pgAdmin4 web UI |

**Note:** pgAdmin4 was incorrectly mapped to 10.255.0.11 (db1) and has been corrected to 10.255.0.4 (apps2).

### db1 (10.255.0.11) Port Mappings

| Service | Old Port | New Port | Internal Port | Notes |
|---------|----------|----------|---------------|-------|
| postgres1 | 5432 | 1024 | 5432 | PostgreSQL database |
| valkey1 | 6379 | 1025 | 6379 | Redis-compatible cache |

## Files Modified

### Host Configurations

1. **[apps1.nix](hosts/apps1.nix)**
   - Fixed stalwartOne port mappings (lines 183-193)
   - Removed conflicting port assignments

2. **[apps2.nix](hosts/apps2.nix)**
   - Updated UniFi ports to use sequential incremental scheme
   - Fixed pgAdmin4 host IP from 10.255.0.11 to 10.255.0.4
   - Updated pgAdmin4 port from 1027 to 1032

3. **[rp1.nix](hosts/rp1.nix)**
   - Updated all nginx stream upstreams to use new ports
   - Updated virtualHost proxy locations to reference new ports

### Specific Changes in rp1.nix

**Nginx Stream Upstreams:**
- dnsOneUI: `10.255.0.3:53443` → `10.255.0.3:1026`
- dnsTwoUI: `10.255.0.4:53443` → `10.255.0.4:1025`
- unifiWeb: `10.255.0.4:8443` → `10.255.0.4:1028`
- unifiComm: `10.255.0.4:8080` → `10.255.0.4:1031`
- unifiStun: `10.255.0.4:3478` → `10.255.0.4:1029`
- unifiDiscovery: `10.255.0.4:10001` → `10.255.0.4:1030`
- stalwartOneHttp: `10.255.0.3:8080` → `10.255.0.3:1030`
- stalwartOneSmtp: `10.255.0.3:25` → `10.255.0.3:1031`
- stalwartOneImap: `10.255.0.3:143` → `10.255.0.3:1032`
- stalwartOneSmtps: `10.255.0.3:465` → `10.255.0.3:1033`
- stalwartOneSubmission: `10.255.0.3:587` → `10.255.0.3:1034`
- stalwartOneImaps: `10.255.0.3:993` → `10.255.0.3:1035`
- stalwartOnePop3s: `10.255.0.3:995` → `10.255.0.3:1036`
- stalwartOneSieve: `10.255.0.3:4190` → `10.255.0.3:1037`

**Nginx virtualHost Locations:**
- docs.reinitialized.net (Hudu): `10.255.0.3:3000` → `10.255.0.3:1025`
- unifi.in.reinitialized.net: `10.255.0.4:8443` → `10.255.0.4:1028`
- pgadmin.in.reinitialized.net: `10.255.0.11:80` → `10.255.0.4:1032`

## Verification Steps

After deploying these changes, verify:

1. **Hudu Access**: https://docs.reinitialized.net should load correctly
2. **DNS Admin UI**: 
   - https://one.dns.reinitialized.net (via 10.255.0.3:1026)
   - https://two.dns.reinitialized.net (via 10.255.0.4:1025)
3. **UniFi Controller**: https://unifi.in.reinitialized.net should load correctly
4. **pgAdmin4**: https://pgadmin.in.reinitialized.net should load correctly
5. **Mail Services**: All SMTP/IMAP/POP3/Sieve protocols should work via rp1 reverse proxy

## Testing Commands

```bash
# Test Hudu web interface
curl -k https://docs.reinitialized.net

# Test DNS admin UI (from mesh network)
curl -k https://10.255.0.3:1026

# Test UniFi web interface
curl -k https://unifi.in.reinitialized.net

# Test pgAdmin4 web interface
curl -k https://pgadmin.in.reinitialized.net

# Test mail SMTP (from rp1)
telnet 10.1.12.2 25

# Test mail IMAP (from rp1)
openssl s_client -connect 10.1.12.2:993
```

## Notes

- All DNS service ports (53, 853) on physical IPs remain unchanged
- DNS resolver references in ACME configs correctly use port 53 (not management ports)
- Physical IP port mappings on apps1/apps2 (e.g., 10.1.11.2:53) remain unchanged
- Only mesh network (10.255.0.x) port mappings were affected by this migration
- Future stalwartTwo service on apps2 has been pre-allocated ports 1033-1040

## Documentation Updates Needed

The following documentation files reference old port schemes and may need updates:

- [docs/architecture/technitium-dns-cluster.md](architecture/technitium-dns-cluster.md)
  - References direct mesh access to ports 5380 and 53443
  - Should be updated to reference new ports 1024-1027

## Related Issues

- Fixed pgAdmin4 host IP error (was pointing to db1 instead of apps2)
- Resolved port conflicts in stalwartOne configuration
- Ensured consistent incremental port allocation across all services
