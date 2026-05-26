# Custom Modules

This directory documents the repository-specific NixOS modules and profiles.

## Modules

| Document | Option or path | Purpose |
|----------|----------------|---------|
| [Secrets Management](secrets.md) | `secrets.*` | Key/value and file-path secret references |
| [Firewall Allowlist/Denylist](firewall.md) | `networking.firewall.allowlist`, `networking.firewall.denylist` | Source-scoped firewall rules generated for nftables or iptables |
| [Mesh Network](meshNetwork.md) | `services.meshNetwork.*` | WireGuard mesh and optional Docker bridge integration |
| [Containers Profile](containers.md) | `modules/profiles/containers/` | Docker host profile, bind-mounted Docker storage, volume migration, image update timer |
| [Standard Profile](standard.md) | `modules/profiles/standard.nix` | Base SSH, sudo-rs, networkd, nftables, user, Nix, and auto-upgrade settings |
| [Mount Data Profile](mountData.md) | `modules/profiles/mountData.nix` | Mounts QEMU `scsi1` at `/mnt/data` |

## Import Paths

`nixosModules.default` exports only these module definitions:

```nix
{
  imports = [
    reinitialized-infra.nixosModules.default
  ];
}
```

It includes:

- `modules/profiles/firewall.nix`
- `modules/profiles/meshNetwork`
- `modules/profiles/secrets.nix`

The repository's host exports are built with `makeConfiguration`, which also imports:

- `modules/hardware/qemu.nix`
- `modules/profiles/standard.nix`
- `modules/profiles/firewall.nix`
- `hosts/<host>.nix`
- `modules/secrets/<host>.nix`, when present

`containers` and `mountData` are not automatic. Add them explicitly for Docker hosts with persistent data:

```nix
modules = [
  "${self}/modules/profiles/containers"
  "${self}/modules/profiles/mountData.nix"
];
```

## Dependencies

| Profile/module | Depends on | Notes |
|----------------|------------|-------|
| `standard` | none | Imported by `makeConfiguration` |
| `firewall` | NixOS firewall | Extends `networking.firewall`; config applies only when the firewall is enabled |
| `secrets` | none | Defines options only; does not create files or decrypt data |
| `meshNetwork` | `secrets` | Imports secrets module; requires `secrets.meshNetwork.file` when enabled |
| `containers` | `meshNetwork`, `secrets`, `containerTools` | Imports these modules and assumes `/mnt/data` is available for Docker storage |
| `mountData` | QEMU second SCSI disk | Uses `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1` |

## Current Host Usage

| Host | Explicit profiles from `flake.nix` |
|------|------------------------------------|
| `devenv` | `containers`, `mountData`, `vscodeServer` |
| `rp1` | `containers`, `mountData`, `vscodeServer` |
| `apps1` | `containers`, `mountData`, `vscodeServer` |
| `apps2` | `containers`, `mountData`, `vscodeServer` |
| `apps3` | `containers`, `mountData`, `vscodeServer` |
| `ai1` | `mountData`, `meshNetwork`, `vscodeServer` |
| `db1` | `containers`, `mountData`, `vscodeServer` |

## Related Docs

- [Profiles Summary](../profiles.md)
- [Library Functions](../library-functions.md)
- [Examples](../examples.md)
