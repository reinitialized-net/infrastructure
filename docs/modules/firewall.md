# Firewall Allowlist/Denylist Module

**Module Path:** `modules/profiles/firewall.nix`

**Import:** Automatically included with `nixosModules.default`

## Overview

Extends the standard NixOS firewall with granular source IP-based allowlisting. Allows fine-grained control over which source IPs can access specific ports, supporting both nftables and iptables backends.

## Features

- Per-port source IP restrictions
- Support for both TCP and UDP protocols
- IPv4, IPv6, or dual-stack support
- CIDR notation for IP ranges
- Automatic backend detection (nftables or iptables)
- Complements existing `networking.firewall` options

## Option: `networking.firewall.allowlist`

### Type

```nix
listOf (submodule)
```

A list of allowlist entries, each specifying a port and allowed source IPs.

### Submodule Options

#### `port`

**Type:** `int`

**Required:** Yes

**Description:** The port number to allow access to.

**Example:** `443`, `8080`, `22`

#### `protocol`

**Type:** `enum [ "tcp" "udp" "tcp_udp" ]`

**Default:** `"tcp"`

**Description:** The protocol for the port. Use `"tcp_udp"` to allow both protocols on the same port.

**Options:**
- `"tcp"` - TCP only
- `"udp"` - UDP only
- `"tcp_udp"` - Both TCP and UDP

#### `ipType`

**Type:** `enum [ "ipv4" "ipv6" "ipv46" ]`

**Default:** `"ipv4"`

**Description:** Which IP versions to apply the rule to.

**Options:**
- `"ipv4"` - IPv4 only
- `"ipv6"` - IPv6 only
- `"ipv46"` - Both IPv4 and IPv6

#### `source`

**Type:** `listOf str`

**Default:** `[ "0.0.0.0/0" ]` (allow from anywhere)

**Description:** List of source IP addresses or CIDR blocks allowed to access the port. When default is used, it allows all IPs (equivalent to standard firewall rules).

**Examples:**
- Single IP: `[ "192.168.1.100" ]`
- CIDR range: `[ "10.0.0.0/8" ]`
- Multiple sources: `[ "192.168.1.0/24" "10.0.0.0/8" ]`
- All IPs: `[ "0.0.0.0/0" ]`

## Usage Examples

### Web Server - Public Access

Allow HTTPS from anywhere:

```nix
{
  networking.firewall = {
    enable = true;
    allowlist = [
      {
        port = 443;
        protocol = "tcp";
        ipType = "ipv4";
        source = [ "0.0.0.0/0" ];  # Allow from anywhere
      }
    ];
  };
}
```

### SSH - Restricted Access

Allow SSH only from trusted networks:

```nix
{
  networking.firewall.allowlist = [
    {
      port = 22;
      protocol = "tcp";
      source = [
        "10.0.0.0/8"          # Internal network
        "192.168.1.0/24"      # Home network
        "203.0.113.50"        # Specific admin IP
      ];
    }
  ];
}
```

### Database - Private Network Only

PostgreSQL accessible only from application servers:

```nix
{
  networking.firewall.allowlist = [
    {
      port = 5432;
      protocol = "tcp";
      source = [
        "10.100.0.10"  # App server 1
        "10.100.0.11"  # App server 2
        "10.100.0.12"  # App server 3
      ];
    }
  ];
}
```

### VPN - UDP Protocol

WireGuard VPN from specific endpoints:

```nix
{
  networking.firewall.allowlist = [
    {
      port = 51820;
      protocol = "udp";
      source = [
        "198.51.100.0/24"  # Remote site A
        "203.0.113.0/24"   # Remote site B
      ];
    }
  ];
}
```

### DNS - Both TCP and UDP

DNS server allowing both protocols:

```nix
{
  networking.firewall.allowlist = [
    {
      port = 53;
      protocol = "tcp_udp";
      source = [ "10.0.0.0/8" ];  # Internal network
    }
  ];
}
```

### IPv6 Support

Web server with IPv6:

```nix
{
  networking.firewall.allowlist = [
    {
      port = 443;
      protocol = "tcp";
      ipType = "ipv46";  # Both IPv4 and IPv6
      source = [ "0.0.0.0/0" ];  # Apply to all (IPv4 will use this)
    }
  ];
}
```

### Complex Multi-Service Setup

```nix
{
  networking.firewall = {
    enable = true;
    allowlist = [
      # HTTPS - public
      {
        port = 443;
        protocol = "tcp";
        ipType = "ipv46";
        source = [ "0.0.0.0/0" ];
      }
      
      # HTTP - redirect only, public
      {
        port = 80;
        protocol = "tcp";
        source = [ "0.0.0.0/0" ];
      }
      
      # SSH - admin networks only
      {
        port = 22;
        protocol = "tcp";
        source = [
          "10.0.0.0/8"
          "192.168.0.0/16"
        ];
      }
      
      # Monitoring - Prometheus scraping
      {
        port = 9090;
        protocol = "tcp";
        source = [ "10.255.0.50" ];  # Monitoring server
      }
      
      # Database - app servers only
      {
        port = 5432;
        protocol = "tcp";
        source = [
          "10.100.0.0/24"  # App server subnet
        ];
      }
      
      # Redis - app servers only
      {
        port = 6379;
        protocol = "tcp";
        source = [ "10.100.0.0/24" ];
      }
      
      # Custom app port
      {
        port = 8080;
        protocol = "tcp";
        source = [ "10.0.0.0/8" ];
      }
    ];
  };
}
```

## Advanced Configuration

### Mixed with Standard Firewall Rules

The allowlist works alongside standard firewall configuration:

```nix
{
  networking.firewall = {
    enable = true;
    
    # Standard allowedTCPPorts still works
    allowedTCPPorts = [ 80 ];  # No source restriction
    
    # Allowlist for source-restricted ports
    allowlist = [
      {
        port = 443;
        source = [ "10.0.0.0/8" ];  # Source restriction
      }
    ];
  };
}
```

### Using with nftables

When using nftables (recommended):

```nix
{
  networking = {
    nftables.enable = true;
    firewall = {
      enable = true;
      package = pkgs.nftables;
      
      allowlist = [
        {
          port = 443;
          protocol = "tcp";
          source = [ "10.0.0.0/8" ];
        }
      ];
    };
  };
}
```

### Using with iptables

Falls back to iptables automatically:

```nix
{
  networking = {
    nftables.enable = false;
    firewall = {
      enable = true;
      package = pkgs.iptables;
      
      allowlist = [
        {
          port = 443;
          protocol = "tcp";
          source = [ "10.0.0.0/8" ];
        }
      ];
    };
  };
}
```

## Implementation Details

### nftables Rules

For nftables, rules are added to the input chain:

```
# Example generated rule for TCP port 443 from 10.0.0.0/8
ip saddr 10.0.0.0/8 tcp dport 443 accept
```

For `tcp_udp` protocol, separate rules are generated:

```
ip saddr 10.0.0.0/8 tcp dport 53 accept
ip saddr 10.0.0.0/8 udp dport 53 accept
```

### iptables Rules

For iptables, rules are added via `extraCommands`:

```
# Example generated rule
iptables -A INPUT -4 -p tcp -s 10.0.0.0/8 --dport 443 -j ACCEPT
```

### Rule Priority

1. Allowlist rules are processed as part of the firewall input chain
2. They are evaluated before the default drop rules
3. Multiple source IPs for the same port create multiple rules

## Best Practices

### 1. Use CIDR Notation for Subnets

Instead of:
```nix
source = [ "192.168.1.1" "192.168.1.2" "192.168.1.3" ... ];
```

Use:
```nix
source = [ "192.168.1.0/24" ];
```

### 2. Restrict Admin Ports

Always restrict administrative ports:

```nix
{
  networking.firewall.allowlist = [
    # Never allow SSH from everywhere
    {
      port = 22;
      source = [ "10.0.0.0/8" ];  # Only internal network
    }
  ];
}
```

### 3. Document Source IPs

Add comments to explain source restrictions:

```nix
{
  networking.firewall.allowlist = [
    {
      port = 3306;
      protocol = "tcp";
      source = [
        "10.100.0.10"  # web-server-1
        "10.100.0.11"  # web-server-2
        "10.100.0.20"  # backup-server
      ];
    }
  ];
}
```

### 4. Test Firewall Rules

After applying changes, test connectivity:

```bash
# Check if port is accessible
nmap -p 443 your-server-ip

# Check from specific source IP
ssh user@your-server 'nft list ruleset' | grep 443
```

### 5. Use with VPN/Mesh Networks

Combine with mesh networking for secure internal communication:

```nix
{
  services.meshNetwork.enable = true;
  
  networking.firewall = {
    # Mesh network is trusted
    trustedInterfaces = [ "wg-mesh" ];
    
    # External services restricted
    allowlist = [
      {
        port = 443;
        source = [ "0.0.0.0/0" ];  # Public
      }
      {
        port = 22;
        source = [ "10.255.0.0/24" ];  # Mesh network only
      }
    ];
  };
}
```

## Debugging

### View Active Rules (nftables)

```bash
# List all nftables rules
nft list ruleset

# Filter for specific port
nft list ruleset | grep "dport 443"
```

### View Active Rules (iptables)

```bash
# List all iptables rules
iptables -L -n -v

# Filter for specific port
iptables -L INPUT -n | grep 443
```

### Test Connectivity

```bash
# From allowed IP
curl https://your-server  # Should work

# From blocked IP
curl https://your-server  # Should timeout/refuse
```

### Common Issues

1. **Rule not applied**: Ensure `networking.firewall.enable = true`
2. **Port still blocked**: Check for conflicting `allowedTCPPorts` settings
3. **IPv6 not working**: Set `ipType = "ipv46"` and verify IPv6 connectivity

## See Also

- [NixOS Firewall Documentation](https://nixos.org/manual/nixos/stable/#sec-firewall)
- [Mesh Network Module](meshNetwork.md) - Uses firewall allowlist
- [Examples](../examples.md) - Complete firewall configurations
