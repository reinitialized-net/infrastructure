# Profiles

Profiles are reusable NixOS modules under `modules/profiles/`. They are composed by `makeConfiguration`, `makeDualExport`, and explicit host module lists in `flake.nix`.

## Summary

| Profile | Path | Auto-imported by repo host builders | Exported through `nixosModules.default` | Explicit import needed |
|---------|------|-------------------------------------|-----------------------------------------|------------------------|
| Standard | `modules/profiles/standard.nix` | Yes | No | No for repo hosts |
| Firewall | `modules/profiles/firewall.nix` | Yes | Yes | No for repo hosts |
| Secrets | `modules/profiles/secrets.nix` | No, except through mesh/containers | Yes | Usually imported by mesh/containers |
| Mesh Network | `modules/profiles/meshNetwork/` | No | Yes | Yes unless imported by another profile |
| Containers | `modules/profiles/containers/` | No | No | Yes |
| Mount Data | `modules/profiles/mountData.nix` | No | No | Yes |

## Standard

[Full reference](modules/standard.md)

Base system configuration:

- systemd-networkd and nftables
- SSH with password auth disabled
- `rnetadmin` administrative user
- sudo-rs
- basic tools
- Nix flakes enabled
- automatic system upgrades
- DBus reconnect timer

Included automatically by `makeConfiguration`.

## Firewall

[Full reference](modules/firewall.md)

Adds source-scoped allowlist and denylist options under `networking.firewall`.

```nix
networking.firewall.allowlist = [
  {
    port = 443;
    protocol = "tcp";
    source = [ "10.0.0.0/8" ];
  }
];
```

Included by `makeConfiguration` and `nixosModules.default`.

## Secrets

[Full reference](modules/secrets.md)

Defines `secrets.<name>.keys`, `secrets.<name>.file`, and `secrets.<name>.description`.

```nix
secrets.meshNetwork = {
  description = "MeshNetwork WireGuard private key";
  file = "/run/secrets/mesh-privatekey";
};
```

The module defines options only; it does not decrypt files or manage permissions. Provision the referenced file on the target before its consumer starts. Use a quoted runtime path for live credentials; `builtins.toFile` and Nix path literals can copy secret contents into the Nix store.

## Mesh Network

[Full reference](modules/meshNetwork.md)

Configures WireGuard `wg-mesh` and, when Docker is enabled, a Docker `backend` bridge network.

```nix
services.meshNetwork = {
  enable = true;
  # nodeId and peers default from meshTopology.nix when hostname is present
};
```

Private keys come from `secrets.meshNetwork.file`. Public keys and endpoints live in `modules/profiles/meshNetwork/meshTopology.nix`.

## Containers

[Full reference](modules/containers.md)

Configures Docker as the OCI backend, Docker storage under `/mnt/data/docker`, daily prune, declarative image update checks, the `migrate-volumes` tool, and restricted Docker SSH migration access.

Use with `mountData`:

```nix
modules = [
  "${self}/modules/profiles/containers"
  "${self}/modules/profiles/mountData.nix"
];
```

Enable mesh networking on container hosts with:

```nix
services.meshNetwork.enable = true;
```

## Mount Data

[Full reference](modules/mountData.md)

Mounts the QEMU second SCSI disk at `/mnt/data`:

```nix
imports = [ "${self}/modules/profiles/mountData.nix" ];
```

The profile enables first-boot formatting and resizing. Only use it where `scsi1` is the intended data disk; provision a blank disk for a new VM and verify existing disks before activation. A mount failure on a production disk is a recovery problem, not permission to format it. See the [storage troubleshooting precautions](modules/mountData.md#troubleshooting).

## Current Host Composition

| Host | Profiles/modules explicitly passed in `flake.nix` |
|------|---------------------------------------------------|
| `devenv` | `vscodeServer`, `containers`, `mountData` |
| `rp1` | `vscodeServer`, `containers`, `mountData` |
| `apps1` | `vscodeServer`, `containers`, `mountData` |
| `apps2` | `vscodeServer`, `containers`, `mountData` |
| `apps3` | `vscodeServer`, `containers`, `mountData` |
| `db1` | `vscodeServer`, `containers`, `mountData` |

All of these also receive the standard, firewall, hardware, host, and host-secret imports from `makeConfiguration`.

## See Also

- [Modules Overview](modules/README.md)
- [Library Functions](library-functions.md)
- [Examples](examples.md)
