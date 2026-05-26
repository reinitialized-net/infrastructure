# Documentation Index

Documentation for the Reinitialized Infrastructure NixOS flake.

## Start Here

- [README](../README.md) - Common commands, current flake outputs, and repository layout
- [Architecture Overview](overview.md) - How the flake, hosts, profiles, and generated tools fit together
- [Examples](examples.md) - Minimal examples that match the current repository patterns

## Core References

### Library And Host Construction

- [Library Functions](library-functions.md)
  - `makeDualExport` - Internal helper used by `flake.nix` to produce both a VMA package and a NixOS configuration
  - `makeConfiguration` - Builds a NixOS configuration and auto-imports host and secrets files
  - `generateVMAImage` - Builds Proxmox VMA archives
  - `forAllSystems` - Creates attrs for `x86_64-linux` and `aarch64-linux`
  - `library/makeUser.nix` - Directly imported user module factory for `/mnt/data`-backed homes

### Modules

- [Modules Overview](modules/README.md)
- [Secrets Management](modules/secrets.md) - `secrets.*`
- [Firewall Allowlist/Denylist](modules/firewall.md) - `networking.firewall.allowlist` and `denylist`
- [Mesh Network](modules/meshNetwork.md) - `services.meshNetwork.*`
- [Containers Profile](modules/containers.md) - Docker host profile and container maintenance timer
- [Mount Data Profile](modules/mountData.md) - `/mnt/data` on QEMU `scsi1`
- [Standard Profile](modules/standard.md) - Base profile imported by `makeConfiguration`
- [Profiles Summary](profiles.md)

### Operations

- [Mesh Network Port Reference](mesh-network-ports.md)
- [Bash Script Tools](bash-script-tools.md)
- [Using makeUser](examples/makeUser.md)

## Architecture Notes

- [Authentik OIDC Auto-Registration](architecture/authentik-oidc-auto-registration.md)
- [Matrix Chat Architecture](architecture/matrix-setup.md)
- [Stalwart Native ACME TLS](architecture/stalwart-native-acme-tls.md)
- [Technitium DNS Cluster](architecture/technitium-dns-cluster.md)

Investigation notes under [docs/investigations/](investigations/) are historical incident writeups. Use them for context, but verify current behavior against source files before making changes.

## Quick Reference

### Current Exported Hosts

| Host | NixOS config | VMA package | Mesh node |
|------|--------------|-------------|-----------|
| `devenv` | `nixosConfigurations.devenv` | `packages.x86_64-linux.devenv` | `10.255.0.1` |
| `rp1` | `nixosConfigurations.rp1` | `packages.x86_64-linux.rp1` | `10.255.0.2` |
| `apps1` | `nixosConfigurations.apps1` | `packages.x86_64-linux.apps1` | `10.255.0.3` |
| `apps2` | `nixosConfigurations.apps2` | `packages.x86_64-linux.apps2` | `10.255.0.4` |
| `apps3` | `nixosConfigurations.apps3` | `packages.x86_64-linux.apps3` | `10.255.0.5` |
| `ai1` | `nixosConfigurations.ai1` | `packages.x86_64-linux.ai1` | `10.255.0.9` |
| `db1` | `nixosConfigurations.db1` | `packages.x86_64-linux.db1` | `10.255.0.11` |

`gs1` is defined in topology and host files but is not currently exported from `flake.nix`.

### Common Tasks

| Task | Start with |
|------|------------|
| Build one host configuration | `nix build path:.#nixosConfigurations.<host>.config.system.build.toplevel` |
| Build one Proxmox VMA image | `nix build path:.#packages.x86_64-linux.<host>` |
| Add a host export | [Library Functions](library-functions.md#makedualexport) |
| Add a Docker host | [Containers Profile](modules/containers.md) and [Mount Data Profile](modules/mountData.md) |
| Add a mesh node | [Mesh Network](modules/meshNetwork.md#adding-a-node) |
| Add source-scoped firewall rules | [Firewall Allowlist/Denylist](modules/firewall.md) |
| Add or change secret keys | [Secrets Management](modules/secrets.md) |
| Deploy from `devenv` | [README Fleet Management](../README.md#fleet-management) |

## Import Behavior

| Module/profile | Imported by `nixosModules.default` | Imported by `makeConfiguration` / `makeDualExport` | Explicit import needed |
|----------------|------------------------------------|-----------------------------------------------------|------------------------|
| `secrets` | Yes | No, except when imported by another passed module such as `meshNetwork` or `containers`; host secret files are auto-imported after option definitions exist | Usually no for current hosts |
| `firewall` | Yes | Yes | No |
| `meshNetwork` | Yes | Only when passed explicitly or imported by another profile | Usually yes for hosts using it |
| `standard` | No | Yes | No when using repo library functions |
| `containers` | No | No | Yes |
| `mountData` | No | No | Yes |

## Contributing To Docs

When changing repository behavior:

1. Update the module, profile, or architecture document closest to the change.
2. Update examples only when they remain valid against source.
3. Update `modules/secrets.example/<host>.nix` when a host consumes a new or renamed secret.
4. Keep historical investigation notes as history; add a superseding note instead of rewriting incident timelines.

Verified against source on May 26, 2026.
