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
| 1029 | stalwartOne | TCP | Stalwart Mail HTTP/web interface |
| 1030 | stalwartOne | TCP | Stalwart Mail SMTP (port 25) |
| 1031 | stalwartOne | TCP | Stalwart Mail IMAP (port 143) |
| 1032 | stalwartOne | TCP | Stalwart Mail SMTPS (port 465) |
| 1033 | stalwartOne | TCP | Stalwart Mail Submission (port 587) |
| 1034 | stalwartOne | TCP | Stalwart Mail IMAPS (port 993) |
| 1035 | stalwartOne | TCP | Stalwart Mail POP3S (port 995) |
| 1036 | stalwartOne | TCP | Stalwart Mail Sieve (port 4190) |
| 1037 | forgejo | TCP | Forgejo Git forge web interface |
| 1038 | jaeger | TCP | Jaeger OTLP gRPC receiver (from OTel Collector) |
| 1039 | jaeger | TCP | Jaeger UI for trace visualization |
| 1040 | grafana | TCP | Grafana metrics visualization web UI |
| 1041 | stalwartOne | TCP | Stalwart Prometheus metrics endpoint (optional) |
| 1042 | stalwartOne | TCP | Stalwart Mail HTTPS listener (port 443, for TLS passthrough) |
| 1043 | authentik-server | TCP | Authentik SSO web UI + API (HTTP/9000) |
| 1044 | ocis | TCP | ownCloud Infinite Scale web UI + WebDAV (HTTP/9200) |

**Next Available Port:** 1045

## apps2 (10.255.0.4)

| Port | Service | Protocol | Description |
|------|---------|----------|-------------|
| 1024 | dnsTwo | TCP | Technitium DNS web admin UI (HTTP/5380) |
| 1025 | dnsTwo | TCP | Technitium DNS web admin UI (HTTPS/53443) |
| 1026 | dnsTwo | TCP | Technitium DNS service (TCP) |
| 1027 | dnsTwo | UDP | Technitium DNS service (UDP) |
| 1027 | unifi | TCP | UniFi Network web admin |
| 1028 | unifi | UDP | UniFi STUN protocol |
| 1029 | unifi | UDP | UniFi device discovery |
| 1030 | unifi | TCP | UniFi device communication |
| 1031 | pgadmin4 | TCP | pgAdmin4 web interface |
| 1032 | stalwartTwo (future) | TCP | Stalwart Mail HTTP/web interface |
| 1033 | stalwartTwo (future) | TCP | Stalwart Mail SMTP (port 25) |
| 1034 | stalwartTwo (future) | TCP | Stalwart Mail SMTPS (port 465) |
| 1035 | stalwartTwo (future) | TCP | Stalwart Mail Submission (port 587) |
| 1036 | stalwartTwo (future) | TCP | Stalwart Mail IMAP (port 143) |
| 1037 | stalwartTwo (future) | TCP | Stalwart Mail IMAPS (port 993) |
| 1038 | stalwartTwo (future) | TCP | Stalwart Mail POP3S (port 995) |
| 1039 | stalwartTwo (future) | TCP | Stalwart Mail Sieve (port 4190) |
| 1040 | cinny | TCP | Cinny Matrix web client |

**Next Available Port:** 1041

## db1 (10.255.0.11)

| Port | Service | Protocol | Description |
|------|---------|----------|-------------|
| 1024 | postgres1 | TCP | PostgreSQL database server |
| 1025 | valkey1 | TCP | Valkey (Redis-compatible) cache |
| 1026 | otel-collector | TCP | OpenTelemetry Collector OTLP gRPC receiver |
| 1027 | otel-collector | TCP | OpenTelemetry Collector OTLP HTTP receiver |
| 1028 | otel-collector | TCP | OpenTelemetry Collector Prometheus metrics exporter |
| 1029 | prometheus | TCP | Prometheus time-series database web UI and API |

**Next Available Port:** 1030

## apps3 (10.255.0.5)

| Port | Service | Protocol | Description |
|------|---------|----------|-------------|
| 1001 | immich-server | TCP | Immich web UI and API |
| 1025 | tuwunel | TCP | Tuwunel Matrix homeserver HTTP API |
| 1026 | paperless-ngx | TCP | Paperless-ngx document management web UI |
| 1027 | pelican-panel | TCP | Pelican Panel game server management web UI |
**Next Available Port:** 1028

## gs1 (10.255.0.6)

| Port | Service | Protocol | Description |
|------|---------|----------|-------------|
| 1024 | wings | TCP | Pelican Wings API (Panel → Wings communication, mesh only) |
| 1025 | wings | TCP | Pelican Wings SFTP (game file management, VLAN accessible on 10.1.11.6:2022) |
| 25565–25600 | game servers | TCP+UDP | Game server ports (Minecraft and others, bound by Wings child containers) |

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
https://unifi.in.reinitialized.net → https://10.255.0.4:1027

# pgAdmin4
https://pgadmin.in.reinitialized.net → http://10.255.0.4:1031

# Matrix homeserver (Tuwunel)
https://matrix.reinitialized.net → http://10.255.0.5:1025

# Cinny Matrix client
https://chat.reinitialized.me → http://10.255.0.4:1040

# Authentik SSO
https://access.reinitialized.net → http://10.255.0.3:1043

# ownCloud Infinite Scale
https://cloud.reinitialized.net → http://10.255.0.3:1044
```

### Mail Services via rp1
Mail protocols are proxied through rp1's nginx stream module with PROXY protocol:
```
Public → rp1 (10.1.12.2) → stalwartOne (10.255.0.3)
  SMTP:25    → mesh:1030
  SMTPS:465  → mesh:1032
  Submission:587 → mesh:1033
  IMAP:143   → mesh:1031
  IMAPS:993  → mesh:1034
  POP3S:995  → mesh:1035
  Sieve:4190 → mesh:1036
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
