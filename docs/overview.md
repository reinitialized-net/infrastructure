# Architecture Overview

## Purpose

This NixOS infrastructure flake is designed to simplify the deployment of NixOS-based virtual machines in Proxmox environments while providing reusable modules for common infrastructure patterns.

## Core Components

### 1. Library Functions

The flake exposes several primary library functions:

- **`makeDualExport`** - Creates both VMA package and nixosSystem from single definition (recommended)
- **`makeUser`** - Creates users with bind-mounted home directories from /mnt/data
- **`forAllSystems`** - Helper for multi-architecture support
- **`generateVMAImage`** - Generates Proxmox VMA (Vzdump) format images
- **`makeConfiguration`** - Creates standard NixOS configurations

### 2. NixOS Modules

Three main custom modules are provided:

- **`secrets`** - Declarative secrets management system
- **`networking.firewall.allowlist`** - Source IP-based firewall rules
- **`services.meshNetwork`** - WireGuard mesh networking for Docker hosts

### 3. Profiles

Pre-configured system profiles for common use cases:

- **standard** - Base configuration with SSH, sudo-rs, and basic tools (auto-included)
- **containers** - Docker with mesh networking support
- **meshNetwork** - WireGuard mesh network with auto-peer discovery from centralized topology
- **mountData** - Data partition mounting configuration
- **firewall** - Advanced firewall with allowlist support
- **secrets** - Declarative secrets management

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
  networking.firewall.allowlist = [ ... ];
}
```

### Proxmox Integration

The VMA image generation process creates ready-to-import Proxmox backups:

1. Builds a complete NixOS system with systemd-boot EFI
2. Creates properly partitioned disk images (ESP + root)
3. Packages as VMA format with QEMU configuration
4. Generates random credentials for initial access

## Workflow

### Using the Dual-Export Pattern (Recommended)

The dual-export pattern is the PRIMARY way to define systems. It allows you to define a system once and export both a VMA image and nixosSystem configuration, eliminating duplication and ensuring consistency.

```nix
{
  outputs = { self, ... }:
    let
      library = import ./library { inherit self; };
      
      # Define systems once using makeDualExport
      dualSystems = {
        myapp = library.makeDualExport "myapp" {
          system = "x86_64-linux";
          vmId = 100;
          cores = 4;
          memory = 8192;
          
          disks = [
            { storage = "local-lvm"; size = 50; }
          ];
          
          networking = [
            { bridge = "vmbr0"; vlan = 100; firewall = true; }
          ];
          
          modules = [ ./hosts/myapp.nix ];
        };
      };
    in
    {
      # Export both outputs from the dual system
      nixosConfigurations.myapp = dualSystems.myapp.nixosSystem;
      packages.x86_64-linux.myapp = dualSystems.myapp.package;
    };
}
```

This pattern ensures that VMA images and nixosSystem configurations stay in sync.

### Building a VM Image

**Note:** Use `makeDualExport` instead of calling `generateVMAImage` directly for new systems.

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

The mesh network module supports auto-peer discovery from a centralized topology:

```nix
# In modules/profiles/meshNetwork/meshTopology.nix, define all nodes once
nodes = {
  node1 = { nodeId = 1; hostname = "node1"; endpoint = "10.1.1.1:51820"; publicKey = "..."; };
  node2 = { nodeId = 2; hostname = "node2"; endpoint = "10.1.1.2:51820"; publicKey = "..."; };
  node3 = { nodeId = 3; hostname = "node3"; endpoint = "10.1.1.3:51820"; publicKey = "..."; };
};

# In your host config, just set nodeId - peers are auto-discovered
services.meshNetwork = {
  enable = true;
  nodeId = 1;  # Automatically discovers node2 and node3 as peers
};
```

## File Structure

```
infrastructure/
├── flake.nix                # Main flake definition
├── library/                 # Library functions
│   ├── default.nix          # Library exports
│   ├── makeDualExport.nix   # Dual-export pattern (PRIMARY)
│   ├── makeConfiguration.nix
│   ├── makeUser.nix         # User with bind-mounted home
│   └── generateVMAImage/
│       ├── default.nix      # VMA image builder
│       └── qemuConfig.nix   # Proxmox VM configuration
├── modules/                 # Custom NixOS modules
│   ├── hardware/
│   │   └── qemu.nix         # QEMU/KVM hardware config
│   ├── profiles/            # System profiles
│   │   ├── standard.nix     # Base config (auto-included)
│   │   ├── mountData.nix    # Secondary disk mounting
│   │   ├── firewall.nix     # Allowlist/denylist firewall
│   │   ├── secrets.nix      # Secrets management
│   │   ├── containers/      # Docker profile (directory)
│   │   └── meshNetwork/     # Mesh network (directory)
│   │       └── meshTopology.nix  # Centralized node definitions
│   ├── secrets/             # Actual secret definitions (gitignored)
│   └── secrets.example/     # Example secret definitions
├── hosts/                   # Host-specific configurations
├── overrides/               # Package overrides
│   └── vma.nix              # Custom QEMU with VMA support
└── docs/                    # Documentation
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
