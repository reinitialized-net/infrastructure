# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
