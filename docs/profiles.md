# Profiles

This flake provides several pre-configured profiles that combine multiple features for common use cases.

## Available Profiles

### Standard Profile

**Auto-imported:** Yes (in all configurations)

**Path:** `modules/profiles/standard.nix`

Base configuration for all systems. Provides:
- SSH server with secure defaults
- sudo-rs (Rust sudo)
- Auto-updates from GitHub
- Basic utilities (bash, vim, shadow)
- nftables firewall
- systemd-networkd
- Standard user (rnetadmin)

[Read full documentation →](modules/standard.md)

**Usage:**
```nix
# Automatically included via library functions
dualSystems.vm = library.makeDualExport "vm" {
  vmId = 100;
  # standard profile is auto-included
};
```

---

### Containers Profile

**Auto-imported:** No (import explicitly)

**Path:** `modules/profiles/containers/`

Docker host configuration with mesh networking. Provides:
- Docker with optimized settings
- Bind-mounted data directory
- Mesh network integration
- cgroups v2 support
- OCI container backend

**Requires:**
- `modules/profiles/mountData.nix`

**Optional:**
- `modules/profiles/meshNetwork` (for container mesh)

[Read full documentation →](modules/containers.md)

**Usage:**
```nix
{
  imports = [
    "${reinitialized-infra}/modules/profiles/mountData.nix"
    "${reinitialized-infra}/modules/profiles/containers"
  ];
  
  services.meshNetwork.enable = true;
}
```

---

### Mesh Network Profile

**Auto-imported:** Via `nixosModules.default`

**Path:** `modules/profiles/meshNetwork/`

WireGuard-based mesh networking. Provides:
- WireGuard VPN configuration
- Docker network integration
- nftables NAT rules
- Helper tools (mesh-keygen, mesh-status, mesh-test)
- Auto-configuration from secrets

[Read full documentation →](modules/meshNetwork.md)

**Usage:**
```nix
{
  services.meshNetwork = {
    enable = true;
    nodeId = 1;
    # privateKeyFile auto-sourced from secrets.meshNetwork.file
    # peers auto-discovered from meshTopology.nix when autoPeers = true (default)
  };
}
```

---

### Firewall Profile

**Auto-imported:** Via `nixosModules.default`

**Path:** `modules/profiles/firewall.nix`

Advanced firewall with source IP allowlist/denylist. Provides:
- Per-port source IP restrictions
- TCP/UDP/both protocol support
- IPv4/IPv6 support
- CIDR notation
- Works with nftables or iptables

[Read full documentation →](modules/firewall.md)

**Usage:**
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

---

### Secrets Profile

**Auto-imported:** Via `nixosModules.default`

**Path:** `modules/profiles/secrets.nix`

Centralized secrets management. Provides:
- Key-value pairs for secrets
- File references
- Integration with external managers
- Type-safe configuration

[Read full documentation →](modules/secrets.md)

**Usage:**
```nix
{
  secrets.my-app = {
    description = "My app secrets";
    keys = {
      apiKey = "secret";
      endpoint = "https://api.example.com";
    };
    file = /run/secrets/private-key;
  };
}
```

---

### Mount Data Profile

**Auto-imported:** No (import explicitly)

**Path:** `modules/profiles/mountData.nix`

Secondary disk management. Provides:
- Auto-formatting
- Auto-resizing
- ext4 filesystem
- Mounts at `/mnt/data`

[Read full documentation →](modules/mountData.md)

**Usage:**
```nix
{
  imports = [
    "${reinitialized-infra}/modules/profiles/mountData.nix"
  ];
  
  # Data disk available at /mnt/data
}
```

---

## Profile Combinations

### Web Server

```nix
{
  # standard profile auto-included
  
  services.nginx.enable = true;
  
  networking.firewall.allowlist = [
    { port = 80; protocol = "tcp"; source = [ "0.0.0.0/0" ]; }
    { port = 443; protocol = "tcp"; source = [ "0.0.0.0/0" ]; }
  ];
}
```

### Database Server

```nix
{
  imports = [
    ./modules/profiles/mountData.nix
  ];
  
  services.postgresql = {
    enable = true;
    dataDir = "/mnt/data/postgres";
  };
  
  networking.firewall.allowlist = [
    {
      port = 5432;
      protocol = "tcp";
      source = [ "10.0.0.0/8" ];  # Internal only
    }
  ];
}
```

### Docker Host

```nix
{
  imports = [
    ./modules/profiles/mountData.nix
    ./modules/profiles/containers
  ];
  
  services.meshNetwork = {
    enable = true;
    nodeId = 1;
    # autoPeers = true is default - peers auto-discovered from meshTopology.nix
    # privateKeyFile is auto-sourced from secrets.meshNetwork.file
  };
}
```

### Secure Application Server

```nix
{
  secrets.my-app = {
    keys = {
      apiKey = "secret";
    };
  };
  
  networking.firewall.allowlist = [
    {
      port = 443;
      protocol = "tcp";
      source = [ "10.0.0.0/8" ];  # Private network only
    }
  ];
}
```

## Profile Import Methods

### Auto-Imported Profiles

These are available automatically when using:

```nix
{
  imports = [
    reinitialized-infra.nixosModules.default
  ];
}
```

Or when using library functions (`makeDualExport`, `makeConfiguration`).

**Auto-imported:**
- standard
- secrets
- firewall
- meshNetwork (module available, needs `enable = true`)

### Explicit Import

Some profiles must be imported explicitly:

```nix
{
  imports = [
    "${reinitialized-infra}/modules/profiles/mountData.nix"
    "${reinitialized-infra}/modules/profiles/containers"
  ];
}
```

**Require explicit import:**
- containers
- mountData

## See Also

- [Library Functions](library-functions.md) - Using profiles with library functions
- [Modules Documentation](modules/README.md) - Detailed module documentation
- [Examples](examples.md) - Complete configuration examples
