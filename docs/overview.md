# Architecture Overview

## Purpose

This repository is a NixOS infrastructure flake for the Reinitialized fleet. It builds Proxmox-compatible VMA images, exports live NixOS configurations for rebuilds, and defines reusable profiles for common host roles: standard VM defaults, Docker hosts, WireGuard mesh networking, secrets wiring, source-scoped firewall rules, and secondary data disks.

The implementation is the source of truth. The most important entry point is `flake.nix`.

## Flake Shape

`flake.nix` imports `library/default.nix`, defines each host with `library.makeDualExport`, and exposes two output families:

```nix
nixosConfigurations.<host>
packages.x86_64-linux.<host>
```

Current exported hosts:

- `devenv`
- `rp1`
- `apps1`
- `apps2`
- `apps3`
- `db1`

`gs1` has a host file, secret example, and mesh topology entry, but its export is commented out in `flake.nix`.

## Core Components

### Library

| File | Role |
|------|------|
| `library/makeDualExport.nix` | Calls `generateVMAImage` and `makeConfiguration` from one host definition |
| `library/makeConfiguration.nix` | Creates `nixpkgs.lib.nixosSystem`, imports hardware, standard profile, firewall profile, host file, and host secrets file when present |
| `library/generateVMAImage/default.nix` | Builds Proxmox VMA output and generated credentials |
| `library/generateVMAImage/qemuConfig.nix` | Produces the Proxmox VM configuration included in the VMA |
| `library/makeUser.nix` | Directly imported module factory for `/mnt/data`-backed users |

Use `makeDualExport` for normal host additions so `nixosConfigurations` and VMA packages stay aligned.

### Profiles And Modules

| Module/profile | Path | How it is used |
|----------------|------|----------------|
| Standard | `modules/profiles/standard.nix` | Auto-imported by `makeConfiguration` |
| Firewall | `modules/profiles/firewall.nix` | Auto-imported by `makeConfiguration`; also exported through `nixosModules.default` |
| Secrets | `modules/profiles/secrets.nix` | Imported by mesh/containers and exported through `nixosModules.default` |
| Mesh Network | `modules/profiles/meshNetwork/` | Explicitly imported by hosts or profiles, and exported through `nixosModules.default` |
| Containers | `modules/profiles/containers/` | Explicitly imported on Docker hosts |
| Mount Data | `modules/profiles/mountData.nix` | Explicitly imported on hosts with a second data disk |
| QEMU Hardware | `modules/hardware/qemu.nix` | Auto-imported by `makeConfiguration` when `hardware = "qemu"` |

### Host Files

Host modules under `hosts/` set static networking, enable mesh networking, define services, and wire secrets into container environments. `makeConfiguration` automatically imports `hosts/<host>.nix` for every host except the special `"standard"` host name.

Live secrets are imported automatically from `modules/secrets/<host>.nix` when that file exists. Secret templates live in `modules/secrets.example/`.

## Network Model

Physical networking is configured with systemd-networkd. Current hosts match the primary NIC by:

```nix
matchConfig.Path = "pci-0000:06:12.0";
```

The WireGuard mesh uses:

- Interface: `wg-mesh`
- Subnet: `10.255.0.0/24`
- Node IP: `10.255.0.<nodeId>`
- Default listen port: `51820`
- Topology file: `modules/profiles/meshNetwork/meshTopology.nix`

Most Docker service-to-service traffic uses mesh IPs and explicitly mapped host ports. See [Mesh Network Port Reference](mesh-network-ports.md).

## Proxmox VMA Generation

`generateVMAImage` builds a VMA archive with:

- systemd-boot and UEFI boot support
- an ESP partition and ext4 root partition on the first disk
- placeholder raw images for additional SCSI disks
- OVMF VARS and TPM state images
- generated Proxmox QEMU config
- a random generated `rnetadmin` password in `CREDENTIALS.txt`

The first configured disk becomes `scsi0` and stores the OS. The `mountData` profile expects the data disk to be `scsi1`.

## Deployment Workflow

The `devenv` host installs generated fleet tools:

- `rebuildHost` - rebuild one target from the repository checkout on `devenv`
- `updateInfra` - rebuild every host listed in mesh topology
- `updateNetworkFirewallRules` - generate and optionally apply OPNsense firewall recommendations from traffic logs

Remote deploys use SSH as `rnetadmin` with `--sudo` on the target. Do not run remote deploy tools with `sudo`.

## File Structure

```text
infrastructure/
├── flake.nix
├── library/
│   ├── default.nix
│   ├── makeDualExport.nix
│   ├── makeConfiguration.nix
│   ├── makeUser.nix
│   └── generateVMAImage/
├── hosts/
│   ├── devenv.nix
│   ├── rp1.nix
│   ├── apps1.nix
│   ├── apps2.nix
│   ├── apps3.nix
│   ├── db1.nix
│   ├── gs1.nix
│   └── devenv/tools/
├── modules/
│   ├── hardware/qemu.nix
│   ├── packages/
│   ├── profiles/
│   ├── secrets.example/
│   └── secrets/        # gitignored live secrets
├── overrides/vma.nix
└── docs/
```

## Next Steps

- [Library Functions](library-functions.md)
- [Modules Overview](modules/README.md)
- [Profiles](profiles.md)
- [Examples](examples.md)
