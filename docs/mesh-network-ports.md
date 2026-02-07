# Mesh Network Port Reference

Quick reference for all mesh network port mappings using the incremental scheme (starting at 1024).

## apps1 (10.255.0.3)

| Port | Service | Protocol | Description |
|------|---------|----------|-------------|
| 1024 | hudu_postgres1 | TCP | PostgreSQL database for Hudu |
| 1025 | hudu1 | TCP | Hudu web application interface |
| 1026 | dnsOne | TCP | Technitium DNS web admin UI (HTTP/5380) |
| 1027 | dnsOne | TCP | Technitium DNS web admin UI (HTTPS/53443) |
| 1028 | dnsOne | TCP | Technitium DNS service (TCP) |
| 1029 | dnsOne | UDP | Technitium DNS service (UDP) |
| 1030 | stalwartOne | TCP | Stalwart Mail HTTP/web interface |
| 1031 | stalwartOne | TCP | Stalwart Mail SMTP (port 25) |
| 1032 | stalwartOne | TCP | Stalwart Mail IMAP (port 143) |
| 1033 | stalwartOne | TCP | Stalwart Mail SMTPS (port 465) |
| 1034 | stalwartOne | TCP | Stalwart Mail Submission (port 587) |
| 1035 | stalwartOne | TCP | Stalwart Mail IMAPS (port 993) |
| 1036 | stalwartOne | TCP | Stalwart Mail POP3S (port 995) |
| 1037 | stalwartOne | TCP | Stalwart Mail Sieve (port 4190) |

**Next Available Port:** 1038

## apps2 (10.255.0.4)

| Port | Service | Protocol | Description |
|------|---------|----------|-------------|
| 1024 | dnsTwo | TCP | Technitium DNS web admin UI (HTTP/5380) |
| 1025 | dnsTwo | TCP | Technitium DNS web admin UI (HTTPS/53443) |
| 1026 | dnsTwo | TCP | Technitium DNS service (TCP) |
| 1027 | dnsTwo | UDP | Technitium DNS service (UDP) |
| 1028 | unifi | TCP | UniFi Network web admin |
| 1029 | unifi | UDP | UniFi STUN protocol |
| 1030 | unifi | UDP | UniFi device discovery |
| 1031 | unifi | TCP | UniFi device communication |
| 1032 | pgadmin4 | TCP | pgAdmin4 web interface |
| 1033 | stalwartTwo (future) | TCP | Stalwart Mail HTTP/web interface |
| 1034 | stalwartTwo (future) | TCP | Stalwart Mail SMTP (port 25) |
| 1035 | stalwartTwo (future) | TCP | Stalwart Mail SMTPS (port 465) |
| 1036 | stalwartTwo (future) | TCP | Stalwart Mail Submission (port 587) |
| 1037 | stalwartTwo (future) | TCP | Stalwart Mail IMAP (port 143) |
| 1038 | stalwartTwo (future) | TCP | Stalwart Mail IMAPS (port 993) |
| 1039 | stalwartTwo (future) | TCP | Stalwart Mail POP3S (port 995) |
| 1040 | stalwartTwo (future) | TCP | Stalwart Mail Sieve (port 4190) |

**Next Available Port:** 1041

## db1 (10.255.0.11)

| Port | Service | Protocol | Description |
|------|---------|----------|-------------|
| 1024 | postgres1 | TCP | PostgreSQL database server |
| 1025 | valkey1 | TCP | Valkey (Redis-compatible) cache |

**Next Available Port:** 1026

## Access Patterns

### Direct Mesh Access
Services are accessed directly via their mesh IP and incremental port:
```bash
# Example: Access Hudu PostgreSQL
psql -h 10.255.0.3 -p 1024 -U hudu

# Example: Access Technitium DNS admin UI
https://10.255.0.3:1026
```

### Via rp1 Reverse Proxy
External services are accessed through rp1's nginx reverse proxy:
```bash
# Hudu web interface
https://docs.reinitialized.net → http://10.255.0.3:1025

# DNS admin UIs (HTTPS passthrough to backend)
https://one.dns.reinitialized.net → https://10.255.0.3:1027
https://two.dns.reinitialized.net → https://10.255.0.4:1025

# DNS admin UIs (legacy HTTP port on rp1, proxied to HTTPS admin)
http://10.1.12.2:53443 → https://10.255.0.3:1027
http://10.1.12.3:53443 → https://10.255.0.4:1025

# Jellyfin media server
https://media.reinitialized.me → http://10.1.11.21:8096

# UniFi controller
https://unifi.in.reinitialized.net → https://10.255.0.4:1028

# pgAdmin4
https://pgadmin.in.reinitialized.net → http://10.255.0.4:1032
```

### Mail Services via rp1
Mail protocols are proxied through rp1's nginx stream module with PROXY protocol:
```
Public → rp1 (10.1.12.2) → stalwartOne (10.255.0.3)
  SMTP:25    → mesh:1031
  SMTPS:465  → mesh:1033
  Submission:587 → mesh:1034
  IMAP:143   → mesh:1032
  IMAPS:993  → mesh:1035
  POP3S:995  → mesh:1036
  Sieve:4190 → mesh:1037
```

## Notes

- **DNS Service (port 53):** Remains on physical IPs (10.1.11.2, 10.1.11.3), not part of incremental scheme
- **Physical IP Services:** External-facing services on physical IPs use standard ports
- **Mesh Network Only:** All ports 1024+ are only accessible via the WireGuard mesh (10.255.0.0/24)
- **Internal Container Ports:** Containers still use their standard ports internally; these are mapped to 1024+ on the mesh interface
- **PROXY Protocol:** Mail services use PROXY protocol to preserve client IPs through the nginx stream proxy

## Port Allocation Strategy

When adding new services:

1. **Find the next available port** for the target host (see "Next Available Port" above)
2. **Increment sequentially** for each exposed service port
3. **Update this reference** document with the new allocation
4. **Document in the investigation file** for historical tracking
5. **Update rp1 nginx config** if the service needs external access

## Related Documentation

- [Port Mapping Scheme Migration](investigations/port-mapping-scheme-migration.md) - Migration history and rationale
- [Technitium DNS Cluster Architecture](architecture/technitium-dns-cluster.md) - DNS cluster setup
