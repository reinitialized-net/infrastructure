# Copilot Instructions for Reinitialized Infrastructure

## Project Overview

NixOS infrastructure flake for building Proxmox VMA (VM Archive) images and managing distributed systems with WireGuard mesh networking. Targets Proxmox VE environments with declarative VM generation, secrets management, and Docker orchestration.

## Architecture Principles

### Dual-Export Pattern (Critical - PRIMARY METHOD)

The `makeDualExport` function is the **PRIMARY and ONLY recommended** pattern for defining systems - it generates BOTH a NixOS configuration AND a VMA package from a single definition:

```nix
devenv = library.makeDualExport "devenv" {
  system = "x86_64-linux";
  vmId = 202;
  modules = [ ./hosts/devenv.nix ];
  # ... VMA-specific config (disks, networking, cores, memory)
};
# Access via: dualSystems.devenv.nixosSystem and dualSystems.devenv.package
```

**Key points:**
- Define systems once in `flake.nix` under `dualSystems`
- Export both `nixosConfigurations.<name>` and `packages.<system>.<name>` from the dual export
- VMA config (vmId, disks, networking) is stripped when creating nixosSystem
- **ALL new hosts MUST use this pattern**
- DO NOT call `generateVMAImage` or `makeConfiguration` directly

### Module Composition

- **standard profile** (`modules/profiles/standard.nix`) is auto-included in ALL systems via `makeConfiguration`
- Profile modules are in `modules/profiles/`:
  - `containers/` (directory with default.nix) - Docker + mesh integration
  - `firewall.nix` - IP allowlist/denylist
  - `meshNetwork/` (directory) - WireGuard mesh with auto-peer discovery
  - `mountData.nix` - Second disk mounting
  - `secrets.nix` - Declarative secrets
- Hardware modules in `modules/hardware/`: currently only `qemu.nix` for Proxmox VMs
- Host-specific configs in `hosts/` import profile modules as needed

## Key Conventions

### Library Functions (library/default.nix)

1. **makeDualExport** - PRIMARY pattern, creates both VMA package and nixosSystem (ALWAYS USE THIS)
2. **makeUser** - Creates users with bind-mounted homes from `/mnt/data` (requires mountData profile)
3. **forAllSystems** - Multi-architecture support helper
4. **generateVMAImage** - INTERNAL: Generates Proxmox VMA images (DO NOT call directly - use makeDualExport)
5. **makeConfiguration** - INTERNAL: Creates nixosSystem (DO NOT call directly - use makeDualExport)

### Secrets Management

Declarative secrets system using `secrets.*` options (defined in `modules/profiles/secrets.nix`):

```nix
# In modules/secrets/<hostname>.nix
secrets.meshNetwork = {
  description = "WireGuard mesh credentials";
  file = /run/secrets/mesh-privatekey;  # For file-based secrets
  keys = {                              # For key-value pairs
    nodeId = 1;
    peers = [ ... ];
  };
};

# Reference elsewhere
config.secrets.meshNetwork.keys.nodeId
config.secrets.meshNetwork.file
```

**Secret files MUST be in `modules/secrets.example/` (checked into git) with real secrets in `modules/secrets/` (gitignored).**

### Networking Patterns

- systemd-networkd is used (NOT NetworkManager)
- `useDHCP = false` at top level, enable per-interface via systemd.network.networks
- Mesh networking uses WireGuard with Docker bridge integration
- **Auto-peer discovery**: Mesh nodes are defined once in `meshTopology.nix`, peers auto-discovered via `autoPeers = true`
- Firewall allowlist/denylist system for source IP-based rules (see `modules/profiles/firewall.nix`)

### Mesh Network Auto-Configuration

- All mesh nodes defined in `modules/profiles/meshNetwork/meshTopology.nix`
- Setting `autoPeers = true` (default) automatically populates peers from topology
- Only need to set `nodeId` in host config - no manual peer configuration needed
- Peers are automatically filtered (excludes self) and formatted correctly

### User Management

- **rnetadmin** - Default admin user (created by standard profile), uses sudo-rs
- **makeUser** - For application users with `/mnt/data` bind mounts
- Users require explicit SSH keys in `openssh.authorizedKeys.keys`
- `mutableUsers = false` - all users must be declared

## Development Workflows

### Building and Deploying

```bash
# Build VMA image for Proxmox import
nix build path:.#packages.x86_64-linux.<hostname>

# Build nixosSystem for testing/development
nix build path:.#nixosConfigurations.<hostname>.config.system.build.toplevel

# Rebuild active system (on NixOS host)
sudo nixos-rebuild switch --flake path:.#<hostname>
```

### Testing Changes

- Use `nixos-rebuild switch` on dev VMs before building production VMAs
- Check the last terminal command exit code - failures often indicate missing options or syntax errors
- VMA builds take significant time due to disk image generation

### Adding New Hosts

1. Create host config in `hosts/<name>.nix`
2. Add dual export in `flake.nix` under `dualSystems`
3. Export both outputs in `nixosConfigurations` and `packages`
4. Create secrets file in `modules/secrets/<name>.nix` if needed

## Common Patterns

### Multi-Disk VMs

```nix
disks = [
  { storage = "hotData"; size = 20; }    # OS disk
  { storage = "coldData"; size = 100; }  # Data disk (needs mountData profile)
];
modules = [ "${inputs.self}/modules/profiles/mountData.nix" ];
```

### Docker Hosts with Mesh

```nix
modules = [
  "${inputs.self}/modules/profiles/containers"  # Enables Docker + mesh
];
# Configure mesh in hosts/<name>.nix:
services.meshNetwork = {
  enable = true;
  nodeId = <unique-id>;
  # With autoPeers = true (default), peers are auto-discovered from meshTopology.nix
  # No need to manually configure privateKeyFile or peers - sourced from secrets
};
```

### Firewall Allowlist/Denylist

```nix
networking.firewall.allowlist = [
  {
    port = 443;
    protocol = "tcp";
    source = [ "10.0.0.0/8" "192.168.1.0/24" ];
  }
];
networking.firewall.denylist = [
  {
    port = 22;
    protocol = "tcp";
    source = [ "192.168.1.100/32" ];
  }
];
```

## Important Files

- **flake.nix** - Flake inputs, dual exports, nixosConfigurations, packages
- **library/makeDualExport.nix** - The core dual-export pattern implementation
- **modules/profiles/standard.nix** - Base config applied to ALL systems
- **modules/profiles/secrets.nix** - Secrets module options definition
- **docs/** - Comprehensive documentation (reference for detailed examples)

## Common Pitfalls

- Don't use `makeConfiguration` or `generateVMAImage` directly - use `makeDualExport`
- Always provide `vmId` for VMA exports (required by Proxmox)
- Secrets files must exist in `modules/secrets/` with examples in `modules/secrets.example/` 
- `/mnt/data` bind mounts require `mountData.nix` profile AND a second disk configured
- systemd-networkd requires explicit interface matching (use `matchConfig.Path` for PCI devices)
