---
description: Build VMA images or NixOS configurations for a host
---

# Build Host Artifacts

This workflow covers building VMA images for Proxmox import and NixOS system configurations for testing.

## Build VMA Image (for Proxmox import)

1. Build the VMA package for the target host:
```bash
nix build path:.#packages.x86_64-linux.<hostname>
```

> **Note:** VMA builds take significant time due to disk image generation.

## Build NixOS Configuration (for testing/development)

1. Build the system toplevel for the target host:
```bash
nix build path:.#nixosConfigurations.<hostname>.config.system.build.toplevel
```

## Rebuild Active System (on a NixOS host directly)

1. Rebuild and switch to the new configuration:
```bash
sudo nixos-rebuild switch --flake path:.#<hostname>
```

## Testing Changes

- Use `nixos-rebuild switch` on dev VMs before building production VMAs
- Check the last terminal command exit code — failures often indicate missing options or syntax errors
