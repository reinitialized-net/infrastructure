# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Current infrastructure point releases use SemVer-style `vMAJOR.MINOR.PATCH` tags from `indev`.

## [Unreleased]

### Fixed

- Seed Infratainer's external live-secret overlay and runtime Forgejo token during `devenv` activation when local gitignored secrets are available.
- Allow automatic update validation, deploy, and fallback `nixos-upgrade` builds from clean `indev` checkouts by importing live host secret modules from `INFRA_SECRETS_DIR`.
- Report a clear mesh private-key secret error when clean flake evaluations are missing the external live secret overlay.
- Avoid unsupported `compgen` usage in Infratainer secret-directory checks so promotion and deploy scripts run under the generated Nix bash.
- Seed Infratainer deployment SSH known_hosts and prefer wrapper-provided `sudo` so fleet deploys can run from the systemd service environment.

## [v0.1.0] - 2026-06-19

### Changed

- Migrate automatic update automation to use the `indev` branch as the release source of truth.
- Add the initial point release process based on annotated Git tags and this changelog.
- Add the `releaseInfra` helper for validated manual releases from `devenv`.

## [1.3.3] - 2026-05-05

### Added

- **Forgejo**: OIDC auto-registration via Authentik
  - Added `FORGEJO__oauth2_client__ENABLE_AUTO_REGISTRATION` and `FORGEJO__oauth2_client__ACCOUNT_LINKING` environment variables to `modules/secrets/apps1.nix`
  - Updated `hosts/apps1.nix` to pass Forgejo secrets to the container
  - Updated `modules/secrets.example/apps1.nix` with Forgejo OIDC configuration
- **Immich**: Updated `modules/secrets.example/apps3.nix` with OIDC environment variables to match real secrets

### Documentation

- Verified OIDC auto-registration status across all Authentik-managed services (Forgejo, Immich, ownCloud)
- OwnCloud (`PROXY_AUTOPROVISION_ACCOUNTS`) and Immich (`IMMICH_OIDC_AUTO_REGISTER`) were already configured

## [1.3.2] - 2026-04-03

### Fixed

- **ownCloud (OCIS)**: Added "Super User" to OIDC role mapping in `apps3.nix` to handle inherited group memberships from Authentik that fail recursive resolution during OIDC flows.

## [1.3.1] - 2026-04-02

### Added

- **Immich**: OIDC authentication configuration via Authentik
  - Added `IMMICH_OIDC_*` environment variables to `modules/secrets/apps3.nix`
  - Enabled auto-registration and configured OIDC issuer/client settings

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

## [1.1.2] - 2026-03-22

### Fixed

- **rp1**: Changed DNS proxy `proxy_bind` from `10.1.12.2` to `10.1.12.3` so rp1's own
  system resolver (source `10.1.12.2`) can get recursive DNS while proxied WAN traffic
  (source `10.1.12.3`) remains denied - requires narrowing Technitium ACL from
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
  - Game port range 25565-25600 (TCP + UDP) open for external game clients
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
