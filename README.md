# Reinitialized Infrastructure Documentation

This documentation covers custom options and features provided by this NixOS infrastructure flake. For standard NixOS options, please refer to the [official NixOS documentation](https://nixos.org/manual/nixos/stable/).

## Table of Contents

1. [Overview](docs/overview.md)
2. [Library Functions](docs/library-functions.md)
   - [generateVMAImage](docs/library-functions.md#generatevmaimage)
   - [makeConfiguration](docs/library-functions.md#makeconfiguration)
   - [makeDualExport](docs/library-functions.md#makedualexport)
   - [makeUser](docs/library-functions.md#makeuser)
3. [Custom Modules](docs/modules/README.md)
   - [Secrets Management](docs/modules/secrets.md)
   - [Firewall Allowlist/Denylist](docs/modules/firewall.md)
   - [Mesh Network](docs/modules/meshNetwork.md)
   - [Containers Profile](docs/modules/containers.md)
4. [Profiles](docs/profiles.md)
5. [Examples](docs/examples.md)

## Quick Start

This flake provides:

- **Dual-Export Pattern**: Define systems once, export both VMA images and nixosSystem configurations
- **Proxmox VMA Image Generation**: Build complete Proxmox-compatible VM images with NixOS
- **User Management**: Create users with properly configured bind-mounted home directories
- **Secrets Management System**: Centralized, declarative secret configuration
- **Mesh Network**: WireGuard-based mesh networking with auto-peer discovery
- **Custom Firewall Rules**: Advanced source IP-based port allowlist/denylist
- **Standard Profiles**: Pre-configured system profiles for common use cases

## Build Instructions

### Available Flake Exports

This flake exports the following systems:

#### NixOS System Configurations
- `nixosConfigurations.devenv` - Development environment VM
- `nixosConfigurations.rp1` - Reverse proxy server VM
- `nixosConfigurations.apps1` - Application server VM

#### Proxmox VMA Packages  
- `packages.x86_64-linux.devenv` - Proxmox VMA image for devenv
- `packages.x86_64-linux.rp1` - Proxmox VMA image for rp1
- `packages.x86_64-linux.apps1` - Proxmox VMA image for apps1

### Building VMA Images for Proxmox

VMA (VM Archive) images are Proxmox-compatible backups that can be imported directly into Proxmox VE.

#### Build a VMA Image

```bash
# Build the VMA image
nix build path:.#packages.x86_64-linux.devenv

# Or use shorthand (if system matches)
nix build path:.#devenv

# Output will be in ./result/
ls -lh result/
# -rw-r--r-- vzdump-qemu-202.vma.zst  # Compressed VMA archive
# -rw-r--r-- CREDENTIALS.txt          # Generated admin password
```

#### Import to Proxmox

```bash
# Copy the VMA to your Proxmox host
scp result/vzdump-qemu-202.vma.zst root@proxmox:/var/lib/vz/dump/

# On the Proxmox host, restore the VM
qmrestore /var/lib/vz/dump/vzdump-qemu-202.vma.zst 202 --storage hotData

# Start the VM
qm start 202
```

#### Important: Save Credentials

The `CREDENTIALS.txt` file contains the randomly generated password for the `rnetadmin` user. Save this securely before deleting the build output:

```bash
cat result/CREDENTIALS.txt
# VM ID: 202
# Hostname: devenv
# Username: rnetadmin  
# Password: <randomly-generated-password>
# Generated: 2026-01-23 12:00:00 UTC
```

### Building for already existing systems

```bash
nixos-rebuild switch --flake path:.#<hostname> --sudo --target-host rnetadmin@<ip> --build-host rnetadmin@<build-ip>
```

### Testing Configurations Before Deployment

Test configurations before applying them:

```bash
# Build without activating
nix build path:.#nixosConfigurations.rp1.config.system.build.toplevel

# Test on the target (boots into new config, auto-reverts if issues)
nixos-rebuild test --flake path:.#rp1 --target-host root@rp1

# Boot into new config on next reboot (doesn't activate immediately)
nixos-rebuild boot --flake path:.#rp1 --target-host root@rp1
```

### Building All Outputs

```bash
# Build all VMA packages
nix build path:.#packages.x86_64-linux.devenv path:.#packages.x86_64-linux.rp1 path:.#packages.x86_64-linux.apps1

# Build all nixosSystem configurations
nix build path:.#nixosConfigurations.devenv.config.system.build.toplevel
nix build path:.#nixosConfigurations.rp1.config.system.build.toplevel
nix build path:.#nixosConfigurations.apps1.config.system.build.toplevel

# Check all flake outputs
nix flake show path:.
```

## Getting Started

Add this flake to your `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    reinitialized-infra.url = "github:reinitialized-net/infrastructure";
  };
  
  outputs = { self, nixpkgs, reinitialized-infra }: {
    # Use the modules
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        reinitialized-infra.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

Or use the library functions directly:

```nix
{
  inputs = {
    reinitialized-infra.url = "github:reinitialized-net/infrastructure";
  };
  
  outputs = { self, reinitialized-infra }: {
    packages.x86_64-linux.my-vm = reinitialized-infra.lib.generateVMAImage "my-vm" {
      system = "x86_64-linux";
      vmId = 100;
      # ... more options
    };
  };
}
```

## Documentation Files

- **[overview.md](docs/overview.md)** - Architecture and design overview
- **[library-functions.md](docs/library-functions.md)** - Detailed library function documentation
- **[modules/](docs/modules/)** - Custom NixOS module documentation
- **[profiles.md](docs/profiles.md)** - Available system profiles
- **[examples.md](docs/examples.md)** - Complete usage examples
