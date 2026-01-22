# Documentation Index

Complete documentation for the Reinitialized Infrastructure NixOS Flake.

## Getting Started

- **[README](../README.md)** - Main documentation entry point with quick start guide
- **[Overview](overview.md)** - Architecture, design philosophy, and file structure

## Core Documentation

### Library Functions

- **[Library Functions](library-functions.md)** - Complete reference for all library functions
  - `generateVMAImage` - Build Proxmox VMA images
  - `makeConfiguration` - Create NixOS configurations
  - `makeUserWithDataHome` - Create users with bind-mounted homes from /mnt/data
  - `forAllSystems` - Helper function for multi-arch support

### Modules

- **[Modules Overview](modules/README.md)** - Introduction to all custom modules

#### Infrastructure Modules

- **[Secrets Management](modules/secrets.md)** - `secrets.*` - Centralized secrets configuration
- **[Firewall Whitelist](modules/firewall.md)** - `networking.firewall.whitelist` - Source IP-based firewall rules
- **[Mesh Network](modules/meshNetwork.md)** - `services.meshNetwork` - WireGuard mesh for Docker hosts

#### Profile Modules

- **[Standard Profile](modules/standard.md)** - Base configuration for all systems
- **[Containers Profile](modules/containers.md)** - Docker host with mesh networking
- **[Mount Data Profile](modules/mountData.md)** - Secondary disk management

### Profiles Summary

- **[Profiles](profiles.md)** - Overview of all available system profiles

## Practical Guides

- **[Examples](examples.md)** - Complete, working configuration examples
  - Simple web server
  - Database server with large disk
  - Multi-host Docker cluster
  - Secure application with firewall
  - Complete infrastructure setup
- **[User Management with Data Homes](examples/makeUserWithDataHome.md)** - Creating users with properly configured home directories

## Documentation by Topic

### By Use Case

**Building Proxmox VMs:**
1. [Library Functions → generateVMAImage](library-functions.md#generatevmaimage)
2. [Standard Profile](modules/standard.md) (auto-included)
3. [Examples → Simple Web Server](examples.md#simple-web-server-vm)

**Docker Orchestration:**
1. [Containers Profile](modules/containers.md)
2. [Mesh Network Module](modules/meshNetwork.md)
3. [Mount Data Profile](modules/mountData.md)
4. [Examples → Multi-Host Docker Cluster](examples.md#multi-host-docker-cluster)

**Security Configuration:**
1. [Firewall Whitelist](modules/firewall.md)
2. [Secrets Management](modules/secrets.md)
3. [Examples → Secure Application](examples.md#secure-application-with-firewall)

**Mesh Networking:**
1. [Mesh Network Module](modules/meshNetwork.md)
2. [Secrets Management](modules/secrets.md) (for credentials)
3. [Examples → Multi-Host Docker Cluster](examples.md#multi-host-docker-cluster)

### By Module Type

**Library Functions:**
- [generateVMAImage](library-functions.md#generatevmaimage)
- [makeConfiguration](library-functions.md#makeconfiguration)
- [makeUserWithDataHome](library-functions.md#makeuserwith datahome)
- [forAllSystems](library-functions.md#forallsystems)

**NixOS Options:**
- [secrets.*](modules/secrets.md)
- [networking.firewall.whitelist](modules/firewall.md)
- [services.meshNetwork.*](modules/meshNetwork.md)

**System Profiles:**
- [standard](modules/standard.md)
- [containers](modules/containers.md)
- [mountData](modules/mountData.md)

## Quick Reference

### Common Tasks

| Task | Documentation |
|------|---------------|
| Build a Proxmox VM | [generateVMAImage](library-functions.md#generatevmaimage) |
| Set up Docker cluster | [Multi-Host Example](examples.md#multi-host-docker-cluster) |
| Configure firewall rules | [Firewall Module](modules/firewall.md) |
| Manage secrets | [Secrets Module](modules/secrets.md) |
| Create mesh network | [Mesh Network Module](modules/meshNetwork.md) |
| Mount data disk | [Mount Data Profile](modules/mountData.md) |
| Create users with data homes | [makeUserWithDataHome](library-functions.md#makeuserwith datahome) |

### Module Quick Links

| Module | Path | Auto-Import |
|--------|------|-------------|
| Secrets | `secrets.*` | Yes |
| Firewall | `networking.firewall.whitelist` | Yes |
| Mesh Network | `services.meshNetwork` | Yes (needs enable) |
| Standard | Profile | Yes |
| Containers | Profile | No |
| Mount Data | Profile | No |

### Configuration Templates

**Minimal VM:**
```nix
packages.x86_64-linux.vm = generateVMAImage "vm" {
  vmId = 100;
};
```

**Docker Host:**
```nix
packages.x86_64-linux.docker = generateVMAImage "docker" {
  vmId = 100;
  disks = [
    { storage = "local-lvm"; size = 50; }
    { storage = "local-lvm"; size = 500; }
  ];
  modules = [
    "${infra}/modules/profiles/mountData.nix"
    "${infra}/modules/profiles/containers.nix"
  ];
};
```

**With Mesh:**
```nix
{
  services.meshNetwork = {
    enable = true;
    nodeId = 1;
    privateKeyFile = /run/secrets/wg-key;
    peers = [ /* ... */ ];
  };
}
```

**With Firewall:**
```nix
{
  networking.firewall.whitelist = [
    {
      port = 443;
      protocol = "tcp";
      source = [ "10.0.0.0/8" ];
    }
  ];
}
```

## Documentation Structure

```
docs/
├── README.md                    # Main entry point
├── INDEX.md                     # This file
├── overview.md                  # Architecture overview
├── library-functions.md         # Library function reference
├── profiles.md                  # System profiles summary
├── examples.md                  # Complete examples
└── modules/
    ├── README.md               # Modules overview
    ├── secrets.md              # Secrets module
    ├── firewall.md             # Firewall module
    ├── meshNetwork.md         # Mesh network module
    ├── containers.md           # Containers profile
    ├── standard.md             # Standard profile
    └── mountData.md           # Mount data profile
```

## Contributing

When adding new features:

1. Document new options in the appropriate module file
2. Add examples to `examples.md`
3. Update this index if adding new documentation files
4. Keep NixOS standard options undocumented (refer to official docs)

## External Resources

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Nix Language Documentation](https://nixos.org/manual/nix/stable/language/)
- [Proxmox VE Documentation](https://pve.proxmox.com/wiki/Main_Page)
- [WireGuard Documentation](https://www.wireguard.com/quickstart/)
- [Docker Documentation](https://docs.docker.com/)

---

**Last Updated:** January 21, 2026

**Repository:** [reinitialized-net/infrastructure](https://github.com/reinitialized-net/infrastructure)
