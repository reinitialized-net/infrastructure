# Reinitialized Infrastructure Documentation

This documentation covers custom options and features provided by this NixOS infrastructure flake. For standard NixOS options, please refer to the [official NixOS documentation](https://nixos.org/manual/nixos/stable/).

## Table of Contents

1. [Overview](docs/overview.md)
2. [Library Functions](docs/library-functions.md)
   - [generateVMAImage](docs/library-functions.md#generatevmaimage)
   - [makeConfiguration](docs/library-functions.md#makeconfiguration)
   - [makeUserWithDataHome](docs/library-functions.md#makeuserwith datahome)
3. [Custom Modules](docs/modules/README.md)
   - [Secrets Management](docs/modules/secrets.md)
   - [Firewall Whitelist](docs/modules/firewall.md)
   - [Mesh Network](docs/modules/meshNetwork.md)
   - [Containers Profile](docs/modules/containers.md)
4. [Profiles](docs/profiles.md)
5. [Examples](docs/examples.md)

## Quick Start

This flake provides:

- **Proxmox VMA Image Generation**: Build complete Proxmox-compatible VM images with NixOS
- **User Management**: Create users with properly configured bind-mounted home directories
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

- **[overview.md](docs/overview.md)** - Architecture and design overview
- **[library-functions.md](docs/library-functions.md)** - Detailed library function documentation
- **[modules/](docs/modules/)** - Custom NixOS module documentation
- **[profiles.md](docs/profiles.md)** - Available system profiles
- **[examples.md](docs/examples.md)** - Complete usage examples
