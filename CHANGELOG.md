# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-04-01

### Added
- **Authentik**: Identity provider (SSO) on apps1 (`access.reinitialized.net`)
  - `authentik-server` container: Web UI + API (port 1043 on mesh)
  - `authentik-worker` container: Background task processor (no external port)
  - Backed by PostgreSQL (`authentik` database) and Valkey (DB index 3) on db1
  - Reverse-proxied through rp1 with large proxy buffers for OIDC tokens
- **ownCloud Infinite Scale (OCIS)**: Cloud storage on apps1 (`cloud.reinitialized.net`)
  - `ocis` container: Web UI + WebDAV (port 1044 on mesh)
  - Configured with external OIDC via Authentik (built-in IDP disabled)
  - Auto-provisioning of user accounts on first OIDC login
  - `PROXY_OIDC_REWRITE_WELLKNOWN` enabled for desktop/mobile client discovery
  - 5TB storage (managed in Proxmox)
  - Reverse-proxied through rp1 with unlimited upload size and extended timeouts

### Changed
- Updated `rp1.nix` with reverse proxy entries for `access.reinitialized.net` and `cloud.reinitialized.net`
- Updated `mesh-network-ports.md` with Authentik (1043) and OCIS (1044) allocations on apps1
- Updated `GEMINI.md` host table to reflect new services on apps1

## [1.2.2] - 2026-03-26

### Fixed
- **apps3 / RustDesk**: Removed port 21114 (`admin web UI`) mapping from `rustdesk-hbbs`
  container — port 21114 is a **Pro-only** feature and does not exist in the OSS
  `rustdesk/rustdesk-server` image; nothing was listening on it, causing 502 Bad Gateway
- **apps3 / RustDesk**: Renumbered hbbr ports down by one after removing port 21114 slot
  (NAT test 1028, hole-punch 1029, hbbs-WS 1030, relay 1031, hbbr-WS 1032)
- **rp1 / RustDesk**: Updated stream upstream addresses to match new port numbers
- **rp1 / RustDesk**: Replaced `ra.reinitialized.net` nginx virtualHost proxy (was pointing
  at non-existent service) with a static informational text/plain response; eliminates 502

## [1.2.1] - 2026-03-26

### Fixed
- **rp1 / RustDesk**: Split port 21116 TCP and UDP into separate nginx stream server blocks
  to avoid mixing TCP-only (`proxy_connect_timeout`) and UDP-only (`proxy_responses`) directives
  in the same block, which caused ambiguous behaviour in angie
- **rp1 / RustDesk**: Changed UDP port 21116 `proxy_responses` from `1` to `0` (unlimited);
  hbbs sends multiple UDP datagrams per heartbeat/registration cycle (punch notifications
  to both peers) — `proxy_responses 1` silently dropped all but the first datagram
- **rp1 / RustDesk**: Increased relay proxy_timeout (21117, 21119) from 600s to 86400s;
  nginx was terminating idle relay connections after 10 minutes, dropping active remote
  desktop sessions

## [1.2.0] - 2026-03-26

### Added
- **RustDesk**: Self-hosted remote desktop server on apps3 (`ra.reinitialized.net`)
  - `rustdesk-hbbs` container: ID/Rendezvous server (ports 1028–1031 on mesh)
  - `rustdesk-hbbr` container: Relay server (ports 1032–1033 on mesh)
  - Shared `rustdesk_data` Docker volume for key pair between hbbs and hbbr
  - rp1 stream-proxies protocol ports 21115–21119 from `10.1.12.4` to apps3 mesh IPs
  - Admin web UI proxied at `https://ra.reinitialized.net` (internal only)
  - Firewall allowlist on rp1 for ports 21115 (tcp), 21116 (tcp+udp), 21117 (tcp), 21118 (tcp), 21119 (tcp) from 0.0.0.0/0

## [1.1.2] - 2026-03-22

### Fixed
- **rp1**: Changed DNS proxy `proxy_bind` from `10.1.12.2` to `10.1.12.3` so rp1's own
  system resolver (source `10.1.12.2`) can get recursive DNS while proxied WAN traffic
  (source `10.1.12.3`) remains denied — requires narrowing Technitium ACL from
  `!10.1.12.0/29` to `!10.1.12.3/32`

## [1.1.1] - 2026-03-21

### Fixed
- **rp1**: Added `proxy_bind 10.1.12.2` to DNS stream proxy blocks so all proxied DNS
  traffic uses a consistent source IP, enabling Technitium's recursion ACL to reliably
  deny public recursion while preserving it for direct internal clients
- **rp1**: Fixed stale comments on DNS upstream blocks that incorrectly referenced mesh routing

## [1.1.0] - 2026-03-19

### Added
- **gs1**: New game server VM (VM 209, VLAN 11, mesh node 6) running Pelican Wings daemon
  - 6 cores, 16GB RAM, 200GB cold data disk for game server storage
  - Pelican Wings container for Docker-managed game servers
  - Game port range 25565–25600 (TCP + UDP) open for external game clients
  - Wings SFTP (port 2022) for game file management within the private LAN
- **Paperless-ngx**: Document management system on apps3 (port 1026)
  - Backed by PostgreSQL (`paperless` database) and Valkey on db1
  - Accessible at `https://paperless.reinitialized.me`
- **Pelican Panel**: Game server management panel on apps3 (port 1027)
  - Backed by PostgreSQL (`pelican` database) and Valkey on db1
  - Internal admin access at `https://game.admin.reinitialized.net`
  - Communicates with Wings on gs1 via mesh network

### Changed
- Updated `meshTopology.nix` to include gs1 (nodeId 6, endpoint 10.1.11.6:51820)
- Updated `rp1.nix` with reverse proxy entries for `paperless.reinitialized.me` and `game.admin.reinitialized.net`
- Updated `apps3.nix` with Paperless-ngx and Pelican Panel container definitions
- Corrected apps3 port reference for immich-server (1001, not 1024) in mesh-network-ports.md

## [1.0.0] - 2026-01-01

### Added
- Initial infrastructure flake with dual-export pattern for Proxmox VMA generation
- Hosts: devenv, rp1, apps1, apps2, apps3, db1, ai1
- WireGuard mesh network with auto-peer discovery
- Reverse proxy (rp1) with nginx stream + virtual hosts, DNS-01 ACME
- Application services: Hudu, Stalwart Mail, Forgejo, Immich, Tuwunel Matrix, Technitium DNS
- Database services: PostgreSQL 18 + pgvector, Valkey 9 (Redis-compatible)
- Observability: OpenTelemetry Collector, Prometheus, Jaeger, Grafana
- Fleet management tools: `rebuildHost`, `updateInfra` on devenv
- Declarative secrets management system
- IP-based allowlist/denylist firewall module (nftables)
