# Custom Modules

This directory contains documentation for all custom NixOS modules provided by this flake.

## Available Modules

### Core Modules

1. **[Secrets Management](secrets.md)** - `secrets`
   - Centralized secrets configuration system
   - Key-value pairs and file references
   - Integration with external secret managers

2. **[Firewall Whitelist](firewall.md)** - `networking.firewall.whitelist`
   - Source IP-based port whitelisting
   - Support for both nftables and iptables
   - IPv4/IPv6 support

3. **[Mesh Network](meshNetwork.md)** - `services.meshNetwork`
   - WireGuard-based mesh networking
   - Docker integration
   - Auto-peer discovery from centralized topology

### Profile Modules

4. **[Containers Profile](containers.md)** - Docker with mesh networking
   - Pre-configured Docker setup
   - Mesh network integration
   - Data volume management

5. **[Standard Profile](standard.md)** - Base system configuration
   - SSH server
   - sudo-rs
   - Basic utilities
   - Firewall with nftables

6. **[Mount Data Profile](mountData.md)** - Data partition mounting
   - Automatic partition detection
   - Auto-formatting
   - Auto-resizing

## Module Usage

All custom modules are automatically available when using `nixosModules.default`:

```nix
{
  inputs = {
    reinitialized-infra.url = "github:reinitialized-net/infrastructure";
  };

  outputs = { self, nixpkgs, reinitialized-infra }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        # Import custom modules
        reinitialized-infra.nixosModules.default
        
        # Use them in your configuration
        {
          secrets.my-app.keys.apiKey = "secret";
          networking.firewall.whitelist = [ ... ];
          services.meshNetwork.enable = true;
        }
      ];
    };
  };
}
```

## Module Categories

### Infrastructure Modules

Modules that provide core infrastructure capabilities:

- **secrets** - Secret management
- **networking.firewall.whitelist** - Advanced firewall rules
- **services.meshNetwork** - Mesh networking

### Profile Modules

Pre-configured system profiles that combine multiple features:

- **standard** - Base configuration for all systems
- **containers** - Docker host setup
- **mountData** - Data partition management

## Module Dependencies

```
standard (base for all systems)
    ├── SSH server
    ├── sudo-rs
    └── auto-updates

containers
    ├── requires: mountData
    ├── requires: meshNetwork (optional)
    └── provides: Docker

meshNetwork
    ├── requires: secrets (optional)
    └── provides: WireGuard mesh

firewall
    └── extends: networking.firewall

secrets
    └── standalone
```

## Next Steps

Read detailed documentation for each module:

- [Secrets Management](secrets.md)
- [Firewall Whitelist](firewall.md)
- [Mesh Network](meshNetwork.md)
- [Containers Profile](containers.md)
