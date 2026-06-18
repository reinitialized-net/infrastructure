# Library Functions

The `library/` directory contains the helper functions used by `flake.nix` to define hosts and build Proxmox images. The flake does not currently export a public `lib` output; inside this repository, import the library with:

```nix
let
  library = import ./library { inherit self; };
in
{
  # use library.makeDualExport, library.makeConfiguration, etc.
}
```

For normal host additions, use `makeDualExport` from `flake.nix`.

## `makeDualExport`

**Path:** `library/makeDualExport.nix`

Creates both outputs for a host from one definition:

- `package` - a Proxmox VMA derivation
- `nixosSystem` - a NixOS configuration

### Signature

```nix
makeDualExport :: host: string -> attrs -> {
  package = derivation;
  nixosSystem = nixosSystem;
}
```

### Options

| Option | Default | Notes |
|--------|---------|-------|
| `system` | `"x86_64-linux"` | Passed to both builders |
| `hardware` | `"qemu"` | Imports `modules/hardware/<hardware>.nix` |
| `modules` | `[]` | Extra NixOS modules passed before host/profile defaults |
| `vmId` | `null` | Required when `exportVMA = true` |
| `cores` | `2` | Proxmox CPU cores |
| `memory` | `4096` | RAM in MiB |
| `enableProtection` | `true` | Proxmox protection flag |
| `disks` | one 25 GiB disk on `hotData` | First disk is OS disk (`scsi0`) |
| `networking` | one `vmbr0` interface on VLAN 200 | Used for generated Proxmox QEMU config |
| `exportVMA` | `true` | Accessing `package` throws if this is true and `vmId` is null |
| `exportNixOS` | `true` | Accessing `nixosSystem` throws when false |

Network entries support `bridge`, `firewall`, optional `vlan`, and optional `macAddress`. Disk entries support `storage` and `size` in GiB.

### Example

```nix
{
  outputs = { self, ... }:
    let
      library = import ./library { inherit self; };

      dualSystems = {
        apps4 = library.makeDualExport "apps4" {
          system = "x86_64-linux";
          vmId = 210;
          memory = 8192;
          disks = [
            { storage = "hotData"; size = 20; }
            { storage = "coldData"; size = 50; }
          ];
          networking = [
            { bridge = "vmbr0"; firewall = false; vlan = 11; }
          ];
          modules = [
            "${self}/modules/profiles/containers"
            "${self}/modules/profiles/mountData.nix"
          ];
        };
      };
    in
    {
      nixosConfigurations.apps4 = dualSystems.apps4.nixosSystem;
      packages.x86_64-linux.apps4 = dualSystems.apps4.package;
    };
}
```

## `makeConfiguration`

**Path:** `library/makeConfiguration.nix`

Builds a NixOS configuration for a host.

### Options

| Option | Default | Notes |
|--------|---------|-------|
| `modules` | `[]` | Extra modules to import first |
| `system` | `"x86_64-linux"` | NixOS system architecture |
| `hardware` | `"qemu"` | Hardware profile name under `modules/hardware/` |

### Automatic Imports

`makeConfiguration host { ... }` imports, in order:

1. Extra modules from `modules`
2. `modules/hardware/<hardware>.nix`
3. `modules/profiles/standard.nix`
4. `modules/profiles/firewall.nix`
5. `hosts/<host>.nix`, unless `host == "standard"`
6. `modules/secrets/<host>.nix`, when the file exists
7. A default `system.stateVersion`

The function passes these `specialArgs`: `self`, `system`, `defaultStateVersion`, `nixpkgsUnstable`, `nixpkgsMaster`, and `lib`.

Build a generated configuration:

```bash
nix build path:.#nixosConfigurations.apps1.config.system.build.toplevel
```

## `generateVMAImage`

**Path:** `library/generateVMAImage/default.nix`

Builds the Proxmox VMA derivation used by `makeDualExport`.

### Required Option

| Option | Notes |
|--------|-------|
| `vmId` | Proxmox VM ID used in the archive name and QEMU config |

Other options mirror `makeDualExport`: `system`, `hardware`, `modules`, `cores`, `memory`, `enableProtection`, `disks`, and `networking`.

### Output

The derivation writes:

```text
result/
├── vzdump-qemu-<vmId>.vma.zst
└── CREDENTIALS.txt
```

`CREDENTIALS.txt` contains the generated password for `rnetadmin`. Save it securely and do not commit it.

### Image Details

- UEFI boot with systemd-boot
- 1 GiB ESP partition
- ext4 root partition sized from the first disk minus 1 GiB
- OVMF VARS disk
- TPM 2.0 state disk
- extra placeholder SCSI disks for each additional disk in `disks`
- generated QEMU config from `library/generateVMAImage/qemuConfig.nix`

Build one exported image:

```bash
nix build path:.#packages.x86_64-linux.rp1
```

## `forAllSystems`

**Path:** `library/default.nix`

Helper around `nixpkgsStable.lib.genAttrs` for:

- `x86_64-linux`
- `aarch64-linux`

Current `flake.nix` uses it to create `packages` attrs, although the defined VMA packages are built from the host definitions in `dualSystems`.

```nix
packages = library.forAllSystems (system: {
  example = /* package for system */;
});
```

## `library/makeUser.nix`

**Path:** `library/makeUser.nix`

Creates a NixOS module for a user whose home is backed by `/mnt/data`. Current host files import this file directly.

### Options

| Option | Default | Notes |
|--------|---------|-------|
| `username` | required | User name |
| `uid` | `null` | Optional UID |
| `group` | `username` | String primary group, or list where the first item is primary and the rest become extra groups |
| `extraGroups` | `[]` | Additional extra groups |
| `gid` | `null` | Optional GID for the primary group |
| `homePermissions` | `"0700"` | tmpfiles mode for `dataPath` |
| `homeDirectory` | `"/home/${username}"` | User home path |
| `dataPath` | `"/mnt/data/${username}"` | Backing directory |
| `extraUserAttrs` | `{}` | Merged into `users.users.<username>` |
| `extraGroupAttrs` | `{}` | Merged into the primary group |

The generated module:

- creates the user and group entries
- creates `dataPath` with `systemd.tmpfiles.rules`
- bind-mounts `dataPath` to `homeDirectory` when the paths differ
- asserts that `/mnt/data` is configured

### Example

```nix
{
  imports = [
    "${self}/modules/profiles/mountData.nix"

    (import "${self}/library/makeUser.nix" {
      username = "servicebot";
      group = "servicebot";
      homeDirectory = "/mnt/data/servicebot";
      dataPath = "/mnt/data/servicebot";
      extraUserAttrs = {
        isSystemUser = true;
        description = "Service bot user";
      };
    })
  ];
}
```

## Related Docs

- [Profiles](profiles.md)
- [Modules Overview](modules/README.md)
- [Using makeUser](examples/makeUser.md)
