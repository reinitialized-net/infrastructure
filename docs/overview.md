# Architecture Overview

## Purpose

This NixOS infrastructure flake is designed to simplify the deployment of NixOS-based virtual machines in Proxmox environments while providing reusable modules for common infrastructure patterns.

## Core Components

### 1. Library Functions

The flake exposes two primary library functions:

- **`generateVMAImage`** - Generates Proxmox VMA (Vzdump) format images suitable for direct import into Proxmox VE
- **`makeConfiguration`** - Creates standard NixOS configurations with sensible defaults

### 2. NixOS Modules

Three main custom modules are provided:

- **`secrets`** - Declarative secrets management system
- **`networking.firewall.whitelist`** - Source IP-based firewall rules
- **`services.meshNetwork`** - WireGuard mesh networking for Docker hosts

### 3. Profiles

Pre-configured system profiles for common use cases:

- **standard** - Base configuration with SSH, sudo-rs, and auto-updates
- **containers** - Docker with mesh networking support
- **meshNetwork** - WireGuard mesh network for distributed systems
- **mountData** - Data partition mounting configuration
- **firewall** - Advanced firewall with whitelist support

### 4. Hardware Modules

- **qemu** - QEMU/KVM VM configuration for Proxmox

## Design Philosophy

### Declarative Everything

All configuration, including secrets references and firewall rules, is declared in Nix expressions. This enables:

- Version control of infrastructure
- Reproducible builds
- Type-safe configuration
- Documentation through code

### Modular Composition

Modules are designed to be composable and independent:

```nix
{
  imports = [
    reinitialized-infra.nixosModules.default
  ];
  
  # Enable features as needed
  services.meshNetwork.enable = true;
  networking.firewall.whitelist = [ ... ];
}
```

### Proxmox Integration

The VMA image generation process creates ready-to-import Proxmox backups:

1. Builds a complete NixOS system with systemd-boot EFI
2. Creates properly partitioned disk images (ESP + root)
3. Packages as VMA format with QEMU configuration
4. Generates random credentials for initial access

## Workflow

### Building a VM Image

```nix
packages.x86_64-linux.my-app = generateVMAImage "my-app" {
  system = "x86_64-linux";
  vmId = 100;
  
  # Hardware resources
  cores = 4;
  memory = 8192;
  
  # Storage configuration
  disks = [
    {
      storage = "local-lvm";
      size = 50;
    }
  ];
  
  # Network configuration
  networking = [
    {
      bridge = "vmbr0";
      vlan = 100;
      firewall = true;
    }
  ];
  
  # Custom modules
  modules = [
    ./my-app-config.nix
  ];
};
```

### Using Secrets

```nix
# Define secrets
secrets.my-app = {
  description = "My application secrets";
  keys = {
    apiKey = "secret-value";
    endpoint = "https://api.example.com";
  };
};

# Reference secrets
services.myapp.apiKey = config.secrets.my-app.keys.apiKey;
```

### Mesh Networking

```nix
services.meshNetwork = {
  enable = true;
  nodeId = 1;
  privateKeyFile = config.secrets.meshNetwork.file;
  peers = config.secrets.meshNetwork.keys.peers;
};
```

## File Structure

```
infrastructure/
├── flake.nix              # Main flake definition
├── library/               # Library functions
│   ├── default.nix        # Library exports
│   ├── makeConfiguration.nix
│   └── generateVMAImage/
│       ├── default.nix    # VMA image builder
│       └── qemuConfig.nix # Proxmox VM configuration
├── modules/               # Custom NixOS modules
│   ├── hardware/
│   │   └── qemu.nix       # QEMU/KVM hardware config
│   ├── profiles/          # System profiles
│   │   ├── standard.nix
│   │   ├── containers.nix
│   │   ├── firewall.nix
│   │   ├── secrets.nix
│   │   └── meshNetwork/
│   └── secrets/           # Secret definitions
│       └── (gitignored)
├── hosts/                 # Host-specific configurations
├── overrides/             # Package overrides
│   └── vma.nix           # Custom QEMU with VMA support
└── docs/                  # Documentation
```

## Integration Points

### With Proxmox

Built images can be imported directly:

```bash
qmrestore /path/to/vzdump-qemu-100.vma.zst 100 --storage local-lvm
```

### With External Secrets

The secrets system can integrate with external secret managers:

```nix
secrets.my-service = {
  file = "/run/secrets/my-service-key";  # From sops-nix, agenix, etc.
  keys = {
    # Reference external secrets
  };
};
```

### With Docker

The mesh network module automatically configures Docker to use the mesh:

```bash
docker network ls  # Shows 'backend' mesh network
docker run --network backend my-container
```

## Next Steps

- [Library Functions Documentation](library-functions.md)
- [Modules Documentation](modules/README.md)
- [Complete Examples](examples.md)
