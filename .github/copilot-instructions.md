# Copilot Instructions for Reinitialized Infrastructure

## Project Overview

NixOS infrastructure flake for building Proxmox VMA (VM Archive) images and managing distributed systems with WireGuard mesh networking. Targets Proxmox VE environments with declarative VM generation, secrets management, and Docker orchestration.

### Current Hosts

| Host | VM ID | Purpose | VLAN | Mesh Node ID |
|------|-------|---------|------|--------------|
| devenv | 202 | Development environment with fleet tools | 200 | 1 |
| rp1 | 203 | Reverse proxy (Technitium DNS, nginx) | 12 | 2 |
| apps1 | 204 | Application server (Hudu, DNS primary) | 11 | 3 |
| apps2 | 205 | Application server (DNS secondary, UniFi) | 11 | 4 |
| apps3 | 207 | Application server (Immich) | 11 | 5 |
| db1 | 206 | Database server (PostgreSQL, Valkey) | 11 | 11 |

### Flake Inputs

- **nixpkgsStable**: `nixos-25.11` (default state version)
- **nixpkgsUnstable**: `nixos-unstable`
- **nixpkgsMaster**: `master`
- **vscodeServer**: VS Code remote server support

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
- `useDHCP = true` at top level by default (can be overridden per-host)
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

### Fleet Management Tools (devenv only)

The `devenv` host includes custom fleet management scripts that simplify deploying changes across the infrastructure. These tools automatically resolve host IPs from `meshTopology.nix` and handle both local and remote deployments.

**`rebuildHost`** - Deploy changes to a single host:
```bash
# Deploy to a remote host (builds on devenv, deploys to target)
rebuildHost apps1

# Deploy to local devenv
rebuildHost devenv

# Use 'boot' instead of 'switch' (activates on next reboot)
rebuildHost rp1 --boot
```

**`updateInfra`** - Deploy changes to ALL hosts in the fleet:
```bash
# Update all hosts defined in meshTopology.nix
updateInfra
```

Both tools:
- Auto-resolve host IPs from `meshTopology.nix`
- Build on devenv and deploy to remote targets via SSH
- Use `rnetadmin` user for remote connections
- Display progress and summary of successful/failed hosts

### Manual Building and Deploying

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
- **library/makeUser.nix** - User creation with bind-mounted homes
- **modules/profiles/standard.nix** - Base config applied to ALL systems (includes firewall.nix)
- **modules/profiles/secrets.nix** - Secrets module options definition
- **modules/profiles/meshNetwork/meshTopology.nix** - Centralized mesh node definitions (used by fleet tools)
- **modules/profiles/containers/default.nix** - Docker configuration with mesh integration
- **hosts/devenv.nix** - Development environment with fleet management tools (`rebuildHost`, `updateInfra`)
- **hosts/rp1.nix** - Reverse proxy with Technitium DNS
- **hosts/apps1.nix** - Application server 1 (Hudu, DNS primary)
- **hosts/apps2.nix** - Application server 2 (DNS secondary, UniFi)
- **docs/** - Comprehensive documentation (reference for detailed examples)

## Common Pitfalls

- Don't use `makeConfiguration` or `generateVMAImage` directly - use `makeDualExport`
- Always provide `vmId` for VMA exports (required by Proxmox)
- Secrets files must exist in `modules/secrets/` with examples in `modules/secrets.example/`
- `/mnt/data` bind mounts require `mountData.nix` profile AND a second disk configured
- systemd-networkd requires explicit interface matching (use `matchConfig.Path` for PCI devices)
- Mesh network private key is sourced from `secrets.meshNetwork.file` - ensure it's configured
- ACME certificates for nginx-proxied services are generated via security.acme with Technitium DNS provider (DNS-01)
- Stalwart Mail Server manages its own TLS certificate via native ACME (HTTP-01 challenge), proxied through rp1 port 80
- Docker volumes are bind-mounted from `/mnt/data/docker/volumes`

# Documentation & Implementation Rules:
- Always investigate for a root cause when diagnosing issues - don't just apply a quick fix without understanding the underlying problem.
- After determining root cause, apply a fix that addresses the root cause directly, rather than implementing a workaround that may only mask symptoms.
- After confirming the fix resolves the issue, document the root cause and the fix under the `/docs/investigations` directory. This documentation should include:
  - A clear description of the root cause
  - The steps taken to identify the root cause
  - The specific changes made to fix the issue
  - Any relevant logs, error messages, or screenshots that illustrate the problem and the solution
- Always look for existing documentation before creating new documentation. If a similar issue has already been documented, update the existing documentation with any new insights or details rather than creating a duplicate entry.
- When implementing or refactoring code, ensure all related documentation is updated to reflect the changes. This includes inline code comments, README files, and any relevant sections in the `/docs` directory.
- If an implementation or refactor takes a reasonable amount of consideration, document the architectural decisions made during the process under `/docs/architecture`. This should include:
  - The different options considered
  - The pros and cons of each option
  - The rationale for the final decision
  - Any trade-offs that were made
- After completing a feature implementation, create tests based off the implementation plan. Ensure the updated code matches the expectations of the implementation plan and that all tests pass successfully. If tests fail, investigate the root cause of the failure and address it before considering the implementation complete.- Always investigate for a root cause when diagnosing issues - don't just apply a quick fix without understanding the underlying problem.
- After determining root cause, apply a fix that addresses the root cause directly, rather than implementing a workaround that may only mask symptoms.
- After confirming the fix resolves the issue, document the root cause and the fix under the `/docs/investigations` directory. This documentation should include:
  - A clear description of the root cause
  - The steps taken to identify the root cause
  - The specific changes made to fix the issue
  - Any relevant logs, error messages, or screenshots that illustrate the problem and the solution
- Always look for existing documentation before creating new documentation. If a similar issue has already been documented, update the existing documentation with any new insights or details rather than creating a duplicate entry.
- When implementing or refactoring code, ensure all related documentation is updated to reflect the changes. This includes inline code comments, README files, and any relevant sections in the `/docs` directory.
- If an implementation or refactor takes a reasonable amount of consideration, document the architectural decisions made during the process under `/docs/architecture`. This should include:
  - The different options considered
  - The pros and cons of each option
  - The rationale for the final decision
  - Any trade-offs that were made
- Whenever you make a feature modification, ensure to update the package version identifier according to [semver rules](https://semver.org) and document the change in the `CHANGELOG.md` file.
- If you believe a task is going to take a long time to complete, consider using subagents. This ensures that the main agent remains responsive and can continue to assist with other tasks while the long-running task is being completed by the subagent, while also reducing timeout issues.
- If you come across something which you feel like applies to copilot-instructions.md, but isn't already documented there, please add it to the file. This file is meant to be a living document that captures all relevant instructions and guidelines for the project, so any new information that is relevant should be added to ensure it remains comprehensive and up-to-date.