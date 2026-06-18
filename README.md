# Reinitialized Infrastructure

NixOS infrastructure flake for building Proxmox VMA images and managing the Reinitialized fleet. The repository defines host configurations, reusable NixOS modules, WireGuard mesh networking, Docker-based services, secret templates, and deployment tools installed on the `devenv` host.

For standard NixOS options, use the [NixOS manual](https://nixos.org/manual/nixos/stable/). This documentation covers repository-specific behavior.

## Quick Start

Show current flake outputs without updating `flake.lock`:

```bash
nix flake show path:. --no-write-lock-file
```

Build one host configuration without activating it:

```bash
nix build path:.#nixosConfigurations.rp1.config.system.build.toplevel
```

Build one Proxmox VMA image:

```bash
nix build path:.#packages.x86_64-linux.rp1
```

The VMA build writes `result/vzdump-qemu-<vmId>.vma.zst` and `result/CREDENTIALS.txt`. Treat `CREDENTIALS.txt` as sensitive; it contains the generated `rnetadmin` password for the image.

## Current Flake Outputs

The source of truth for exported hosts is `flake.nix`. As of this update, these hosts are exported as both `nixosConfigurations.<host>` and `packages.x86_64-linux.<host>`:

| Host | VM ID | VLAN | Mesh IP | Purpose |
|------|-------|------|---------|---------|
| `devenv` | 202 | 200 | `10.255.0.1` | Development VM and fleet management tools |
| `rp1` | 203 | 12 | `10.255.0.2` | Reverse proxy, public ingress, DNS/mail stream proxying |
| `apps1` | 204 | 11 | `10.255.0.3` | Hudu, Technitium DNS primary, Stalwart, Forgejo, Jaeger, Grafana, Authentik |
| `apps2` | 205 | 11 | `10.255.0.4` | Technitium DNS secondary, UniFi, pgAdmin, Redis Insight, Forgejo Runner, Cinny |
| `apps3` | 207 | 11 | `10.255.0.5` | Immich, Tuwunel Matrix, Paperless-ngx, Pelican Panel, OCIS, SearXNG |
| `db1` | 206 | 11 | `10.255.0.11` | PostgreSQL, Valkey, OpenTelemetry Collector, Prometheus |

`gs1` exists in `hosts/`, `modules/secrets.example/`, and `meshTopology.nix`, but it is commented out in `flake.nix`; `.#gs1` builds and deploys do not work until it is exported.

## Common Commands

Build all exported NixOS configurations without generating VMA images:

```bash
nix build \
  path:.#nixosConfigurations.devenv.config.system.build.toplevel \
  path:.#nixosConfigurations.rp1.config.system.build.toplevel \
  path:.#nixosConfigurations.apps1.config.system.build.toplevel \
  path:.#nixosConfigurations.apps2.config.system.build.toplevel \
  path:.#nixosConfigurations.apps3.config.system.build.toplevel \
  path:.#nixosConfigurations.db1.config.system.build.toplevel
```

Build a Proxmox image for one host:

```bash
nix build path:.#packages.x86_64-linux.apps1
```

Import a built VMA on a Proxmox host:

```bash
scp result/vzdump-qemu-204.vma.zst root@proxmox:/var/lib/vz/dump/
qmrestore /var/lib/vz/dump/vzdump-qemu-204.vma.zst 204 --storage hotData
qm start 204
```

Format changed Nix files when the formatter is available:

```bash
nixfmt-rfc-style <file>.nix
```

This flake does not define `checks`, `formatter`, `apps`, or `devShells`, so do not assume `nix fmt` or `nix flake check` provides repository validation.

## Fleet Management

The `devenv` host installs generated tools from `hosts/devenv/tools/`.

Deploy one host:

```bash
rebuildHost apps1
rebuildHost rp1 --boot
rebuildHost devenv
```

Deploy every host listed in `meshTopology.nix`:

```bash
updateInfra
```

Important behavior:

- `rebuildHost <remote>` and `updateInfra` use SSH as `rnetadmin` and pass `--sudo` to the remote rebuild.
- Do not run remote deploys with `sudo`; the scripts reject root because root breaks the SSH key flow.
- `rebuildHost devenv` is local and uses `sudo nixos-rebuild` internally.
- `updateInfra` derives its host list from `modules/profiles/meshNetwork/meshTopology.nix`, not from `flake.nix`; verify flake exports before deploying a newly added topology host.

Generate OPNsense firewall rule recommendations from traffic logs:

```bash
updateNetworkFirewallRules --dry-run
```

Credentials come from `secrets.opnsenseFirewall` on `devenv`, or from environment variables documented in [Secrets Management](docs/modules/secrets.md).

## Repository Layout

| Path | Purpose |
|------|---------|
| `flake.nix` | Inputs, host definitions, `nixosConfigurations`, VMA packages |
| `library/` | Internal helpers for NixOS configs, dual exports, VMA generation, and user modules |
| `library/generateVMAImage/` | Proxmox VMA builder and generated QEMU config |
| `hosts/` | Host-specific NixOS modules |
| `hosts/devenv/tools/` | Generated deployment and firewall helper scripts |
| `modules/profiles/` | Standard, firewall, secrets, mesh, containers, and data-disk profiles |
| `modules/packages/` | Package overrides used by service hosts |
| `modules/secrets.example/` | Checked-in templates for live secrets |
| `modules/secrets/` | Live secrets, ignored by git |
| `docs/` | Architecture, module, example, and investigation notes |
| `overrides/vma.nix` | QEMU package override with VMA support |

## Documentation

- [Documentation Index](docs/INDEX.md)
- [Architecture Overview](docs/overview.md)
- [Library Functions](docs/library-functions.md)
- [Module Documentation](docs/modules/README.md)
- [Profiles](docs/profiles.md)
- [Examples](docs/examples.md)
- [Mesh Network Port Reference](docs/mesh-network-ports.md)

## Secrets

Do not commit live secrets. Real secrets live in `modules/secrets/<host>.nix`; templates live in `modules/secrets.example/<host>.nix`.

`makeConfiguration` imports `modules/secrets/<host>.nix` automatically when the file exists. When adding or renaming a secret key used by a host, update the matching example file.
