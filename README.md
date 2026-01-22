# Reinitialized Infrastructure Documentation

This documentation covers custom options and features provided by this NixOS infrastructure flake. For standard NixOS options, please refer to the [official NixOS documentation](https://nixos.org/manual/nixos/stable/).

## Table of Contents

1. [Overview](overview.md)
2. [Library Functions](library-functions.md)
   - [generateVMAImage](library-functions.md#generatevmaimage)
   - [makeConfiguration](library-functions.md#makeconfiguration)
3. [Custom Modules](modules/README.md)
   - [Secrets Management](modules/secrets.md)
   - [Firewall Whitelist](modules/firewall.md)
   - [Mesh Network](modules/mesh-network.md)
   - [Containers Profile](modules/containers.md)
4. [Profiles](profiles.md)
5. [Examples](examples.md)

## Quick Start

This flake provides:

- **Proxmox VMA Image Generation**: Build complete Proxmox-compatible VM images with NixOS
- **Secrets Management System**: Centralized, declarative secret configuration
- **Mesh Network**: WireGuard-based mesh networking for Docker containers
- **Custom Firewall Rules**: Advanced source IP-based port whitelisting
- **Standard Profiles**: Pre-configured system profiles for common use cases

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

- **[overview.md](overview.md)** - Architecture and design overview
- **[library-functions.md](library-functions.md)** - Detailed library function documentation
- **[modules/](modules/)** - Custom NixOS module documentation
- **[profiles.md](profiles.md)** - Available system profiles
- **[examples.md](examples.md)** - Complete usage examples
