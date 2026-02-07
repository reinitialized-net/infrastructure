# Documentation Index

Complete documentation for the Reinitialized Infrastructure NixOS Flake.

## Getting Started

- **[README](../README.md)** - Main documentation entry point with quick start guide
- **[Overview](overview.md)** - Architecture, design philosophy, and file structure

## Core Documentation

### Library Functions

- **[Library Functions](library-functions.md)** - Complete reference for all library functions
  - `makeDualExport` - Export both VMA package and nixosSystem (recommended)
  - `makeUser` - Create users with bind-mounted homes from /mnt/data
  - `forAllSystems` - Helper function for multi-arch support
  - `generateVMAImage` - Build Proxmox VMA images
  - `makeConfiguration` - Create NixOS configurations

### Modules

- **[Modules Overview](modules/README.md)** - Introduction to all custom modules

#### Infrastructure Modules

- **[Secrets Management](modules/secrets.md)** - `secrets.*` - Centralized secrets configuration
- **[Firewall Allowlist/Denylist](modules/firewall.md)** - `networking.firewall.allowlist` - Source IP-based firewall rules
- **[Mesh Network](modules/meshNetwork.md)** - `services.meshNetwork` - WireGuard mesh with auto-peer discovery

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
- **[User Management with Data Homes](examples/makeUser.md)** - Creating users with properly configured home directories

## Architecture Documentation

- **[Technitium DNS Cluster](architecture/technitium-dns-cluster.md)** - Authoritative DNS cluster with centralized certificate management

## Documentation by Topic

### By Use Case

**Building Proxmox VMs:**
1. [Library Functions → makeDualExport](library-functions.md#makedualexport)
2. [Standard Profile](modules/standard.md) (auto-included)
3. [Examples → Simple Web Server](examples.md#simple-web-server-vm)

**Docker Orchestration:**
1. [Containers Profile](modules/containers.md)
2. [Mesh Network Module](modules/meshNetwork.md)
3. [Mount Data Profile](modules/mountData.md)
4. [Examples → Multi-Host Docker Cluster](examples.md#multi-host-docker-cluster)

**Security Configuration:**
1. [Firewall Allowlist/Denylist](modules/firewall.md)
2. [Secrets Management](modules/secrets.md)
3. [Examples → Secure Application](examples.md#secure-application-with-firewall)

**Mesh Networking:**
1. [Mesh Network Module](modules/meshNetwork.md)
2. [Secrets Management](modules/secrets.md) (for credentials)
3. [Examples → Multi-Host Docker Cluster](examples.md#multi-host-docker-cluster)

### By Module Type

**Library Functions:**
- [makeDualExport](library-functions.md#makedualexport) (PRIMARY)
- [makeUser](library-functions.md#makeuser)
- [forAllSystems](library-functions.md#forallsystems)
- [generateVMAImage](library-functions.md#generatevmaimage)
- [makeConfiguration](library-functions.md#makeconfiguration)

**NixOS Options:**
- [secrets.*](modules/secrets.md)
- [networking.firewall.allowlist](modules/firewall.md)
- [services.meshNetwork.*](modules/meshNetwork.md)

**System Profiles:**
- [standard](modules/standard.md)
- [containers](modules/containers.md)
- [mountData](modules/mountData.md)

## Quick Reference

### Common Tasks

| Task | Documentation |
|------|---------------|
| Build a Proxmox VM | [makeDualExport](library-functions.md#makedualexport) |
| Set up Docker cluster | [Multi-Host Example](examples.md#multi-host-docker-cluster) |
| Configure firewall rules | [Firewall Module](modules/firewall.md) |
| Manage secrets | [Secrets Module](modules/secrets.md) |
| Create mesh network | [Mesh Network Module](modules/meshNetwork.md) |
| Mount data disk | [Mount Data Profile](modules/mountData.md) |
| Create users with data homes | [makeUser](library-functions.md#makeuser) |
| Deploy fleet changes | [Fleet Management](#fleet-management-tools) |

### Module Quick Links

| Module | Path | Auto-Import |
|--------|------|-------------|
| Secrets | `secrets.*` | Yes |
| Firewall | `networking.firewall.allowlist` | Yes |
| Mesh Network | `services.meshNetwork` | Yes (needs enable) |
| Standard | Profile | Yes |
| Containers | Profile | No |
| Mount Data | Profile | No |

### Configuration Templates

**Minimal VM (using makeDualExport):**
```nix
dualSystems.myvm = library.makeDualExport "myvm" {
  vmId = 100;
  modules = [ ./hosts/myvm.nix ];
};
# Export: nixosConfigurations.myvm = dualSystems.myvm.nixosSystem;
# Export: packages.x86_64-linux.myvm = dualSystems.myvm.package;
```

**Docker Host:**
```nix
dualSystems.docker = library.makeDualExport "docker" {
  vmId = 100;
  disks = [
    { storage = "local-lvm"; size = 50; }
    { storage = "local-lvm"; size = 500; }
  ];
  modules = [
    "${inputs.self}/modules/profiles/mountData.nix"
    "${inputs.self}/modules/profiles/containers"
  ];
};
```

**With Mesh (autoPeers - recommended):**
```nix
{
  services.meshNetwork = {
    enable = true;
    nodeId = 1;
    # autoPeers = true is default - peers auto-discovered from meshTopology.nix
    # privateKeyFile is auto-sourced from secrets.meshNetwork.file
  };
}
```

**With Firewall:**
```nix
{
  networking.firewall.allowlist = [
    {
      port = 443;
      protocol = "tcp";
      source = [ "10.0.0.0/8" ];
    }
  ];
}
```

### Fleet Management Tools

Available on the `devenv` host for deploying changes across the infrastructure:

**`rebuildHost <hostname>`** - Deploy to a single host
```bash
rebuildHost apps1           # Deploy to remote host
rebuildHost devenv          # Deploy locally
rebuildHost rp1 --boot      # Activate on next reboot
```

**`updateInfra`** - Deploy to all hosts in the fleet
```bash
updateInfra                 # Updates all hosts from meshTopology.nix
```

## Documentation Structure

```
docs/
├── INDEX.md                     # This file
├── overview.md                  # Architecture overview
├── library-functions.md         # Library function reference
├── profiles.md                  # System profiles summary
├── examples.md                  # Complete examples
├── bash-script-tools.md         # Bash tool organization patterns
├── mesh-network-ports.md        # Port allocation reference
├── architecture/
│   └── technitium-dns-cluster.md # DNS cluster architecture
├── examples/
│   └── makeUser.md              # User management examples
├── investigations/
│   ├── nixos-rebuild-access-denied.md
│   ├── port-mapping-scheme-migration.md
│   ├── stalwart-imap-auth-failure.md
│   └── stalwart-migration-lock-loop.md
└── modules/
    ├── README.md                # Modules overview
    ├── secrets.md               # Secrets module
    ├── firewall.md              # Firewall module
    ├── meshNetwork.md           # Mesh network module
    ├── containers.md            # Containers profile
    ├── standard.md              # Standard profile
    └── mountData.md             # Mount data profile
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

**Last Updated:** February 7, 2026

**Repository:** [reinitialized-net/infrastructure](https://github.com/reinitialized-net/infrastructure)
