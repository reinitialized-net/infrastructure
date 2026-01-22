# Library Functions

This flake provides library functions for building NixOS configurations and Proxmox VM images.

## Available Functions

### `generateVMAImage`

Generates a Proxmox-compatible VMA (Vzdump) format VM image with a complete NixOS system.

#### Signature

```nix
generateVMAImage :: String -> AttrSet -> Derivation
```

#### Parameters

**`host`** (String, required)
- The hostname for the VM
- Used in the VM configuration and as the system hostname
- Example: `"my-app-server"`

**Configuration AttrSet:**

**`vmId`** (Integer, required)
- Unique Proxmox VM ID
- Must be unique within your Proxmox cluster
- Example: `100`

**`system`** (String, optional)
- Target system architecture
- Default: `"x86_64-linux"`
- Options: `"x86_64-linux"`, `"aarch64-linux"`

**`cores`** (Integer, optional)
- Number of CPU cores to allocate
- Default: `2`
- Example: `4`

**`memory`** (Integer, optional)
- RAM in megabytes
- Default: `4096` (4 GB)
- Example: `8192` (8 GB)

**`hardware`** (String, optional)
- Hardware profile to use
- Default: `"qemu"`
- The profile must exist in `modules/hardware/`

**`enableProtection`** (Boolean, optional)
- Enable Proxmox VM protection (prevents accidental deletion)
- Default: `true`
- Set to `false` for testing/development VMs

**`disks`** (List of AttrSet, optional)
- Disk configuration
- Default: Single 25GB disk on `"hotData"` storage
- Each disk has:
  - `storage`: Proxmox storage name
  - `size`: Disk size in GB

**`networking`** (List of AttrSet, optional)
- Network interface configuration
- Default: Single interface on `vmbr0` with DHCP on VLAN 200
- Each interface has:
  - `bridge`: Proxmox bridge name
  - `firewall`: Enable Proxmox firewall (boolean)
  - `vlan`: VLAN tag (integer, optional)
  - `useDHCP`: Enable DHCP (boolean)
  - `macAddress`: MAC address (string, optional, defaults to auto-generated)

**`modules`** (List, optional)
- Additional NixOS modules to include
- Default: `[]`
- Example: `[ ./my-app.nix ]`

#### Example Usage

##### Minimal Example

```nix
{
  packages.x86_64-linux.basic-vm = library.generateVMAImage "basic-vm" {
    system = "x86_64-linux";
    vmId = 100;
  };
}
```

This creates a VM with:
- VM ID 100
- 2 CPU cores, 4GB RAM
- Single 25GB disk
- DHCP networking on VLAN 200

##### Advanced Example

```nix
{
  packages.x86_64-linux.app-server = library.generateVMAImage "app-server" {
    system = "x86_64-linux";
    vmId = 150;
    
    # Resource allocation
    cores = 8;
    memory = 16384;
    
    # Enable protection for production
    enableProtection = true;
    
    # Multiple disks
    disks = [
      {
        storage = "fast-ssd";
        size = 50;  # OS + apps
      }
      {
        storage = "bulk-storage";
        size = 500; # Data
      }
    ];
    
    # Multiple network interfaces
    networking = [
      {
        bridge = "vmbr0";
        firewall = true;
        vlan = 100;  # Management network
        useDHCP = true;
      }
      {
        bridge = "vmbr1";
        firewall = false;
        vlan = 200;  # Application network
        useDHCP = false;  # Static IP configured elsewhere
      }
    ];
    
    # Custom configuration
    modules = [
      ./app-configuration.nix
      {
        # Inline configuration
        networking.firewall.whitelist = [
          {
            port = 443;
            protocol = "tcp";
            source = [ "10.0.0.0/8" ];
          }
        ];
      }
    ];
  };
}
```

#### Output

The function returns a derivation that builds:

1. **VMA Archive** - `vzdump-qemu-<vmId>.vma.zst`
   - Compressed Proxmox backup format
   - Ready to import with `qmrestore`
   - Contains:
     - Root filesystem image
     - EFI boot partition
     - TPM state
     - VM configuration

2. **Credentials File** - `CREDENTIALS.txt`
   - Contains generated password for `rnetadmin` user
   - **IMPORTANT**: Save this password securely before deleting the file
   - Format:
     ```
     VM ID: 150
     Hostname: app-server
     Username: rnetadmin
     Password: <randomly-generated-32-char-password>
     ```

#### Building the Image

```bash
# Build the image
nix build .#packages.x86_64-linux.app-server

# The output is in ./result/
ls -lh result/
# -rw-r--r-- vzdump-qemu-150.vma.zst
# -rw-r--r-- CREDENTIALS.txt

# Import to Proxmox (run on Proxmox host)
qmrestore result/vzdump-qemu-150.vma.zst 150 --storage local-lvm
```

#### Technical Details

##### Boot Configuration

- **Boot Loader**: systemd-boot (UEFI)
- **Partition Layout**:
  - 1GB ESP (EFI System Partition) - FAT32
  - Remainder: root partition - ext4
  - 4MB EFI disk (OVMF VARS)
  - 4MB TPM 2.0 state
- **Root Filesystem**: ext4 with automatic growth on first boot

##### Default System Configuration

Includes the `standard` profile which provides:
- SSH server with public key authentication
- `sudo-rs` (Rust implementation of sudo)
- Auto-updates from GitHub
- Basic system utilities (bash, vim, shadow)
- `rnetadmin` user with wheel group membership

##### Hardware Support

- VirtIO SCSI for disk I/O
- VirtIO network devices
- QEMU guest agent integration
- TPM 2.0 support
- KVM acceleration

##### Network Configuration

- Uses systemd-networkd
- NetworkManager disabled
- nftables firewall
- DHCP or static IP configuration

---

### `makeConfiguration`

Creates a standard NixOS system configuration with sensible defaults. Simpler than `generateVMAImage` - use this when you don't need Proxmox VMA format.

#### Signature

```nix
makeConfiguration :: String -> AttrSet -> NixOSConfiguration
```

#### Parameters

**`host`** (String, required)
- The hostname for the configuration
- Used to locate host-specific configuration in `modules/hosts/`
- Example: `"webserver"`

**Configuration AttrSet:**

**`system`** (String, optional)
- Target system architecture
- Default: `"x86_64-linux"`
- Options: `"x86_64-linux"`, `"aarch64-linux"`

**`hardware`** (String, optional)
- Hardware profile to use
- Default: `"qemu"`
- Must exist in `modules/hardware/`

**`modules`** (List, optional)
- Additional NixOS modules to include
- Default: `[]`
- Example: `[ ./custom-config.nix ]`

#### Example Usage

```nix
{
  nixosConfigurations.webserver = library.makeConfiguration "webserver" {
    system = "x86_64-linux";
    hardware = "qemu";
    modules = [
      ./webserver-config.nix
      {
        services.nginx.enable = true;
      }
    ];
  };
}
```

#### What It Includes

Automatically imports:
- Hardware module (`modules/hardware/${hardware}.nix`)
- Standard profile (`modules/profiles/standard.nix`)
- Host-specific config (`modules/hosts/${host}.nix`) if it exists
- Sets `system.stateVersion` to the flake default

#### Building

```bash
# Build the system
nixos-rebuild build --flake .#webserver

# Or activate directly
nixos-rebuild switch --flake .#webserver
```

---

### `forAllSystems`

Helper function that applies a function to all supported systems.

#### Signature

```nix
forAllSystems :: (String -> AttrSet) -> AttrSet
```

#### Supported Systems

- `x86_64-linux`
- `aarch64-linux`

#### Example Usage

```nix
{
  packages = library.forAllSystems (system: {
    my-package = pkgs.hello;
  });
}
```

Expands to:

```nix
{
  packages = {
    x86_64-linux.my-package = pkgs.hello;
    aarch64-linux.my-package = pkgs.hello;
  };
}
```

---

## Complete Example Flake

```nix
{
  description = "My infrastructure";

  inputs = {
    reinitialized-infra.url = "github:reinitialized-net/infrastructure";
  };

  outputs = { self, reinitialized-infra }:
    let
      library = reinitialized-infra.lib;
    in
    {
      # Proxmox VM images
      packages = library.forAllSystems (system: {
        # Web server VM
        web = library.generateVMAImage "web" {
          inherit system;
          vmId = 100;
          cores = 4;
          memory = 8192;
          modules = [ ./web-config.nix ];
        };
        
        # Database VM
        db = library.generateVMAImage "db" {
          inherit system;
          vmId = 101;
          cores = 8;
          memory = 32768;
          disks = [
            { storage = "local-lvm"; size = 50; }
            { storage = "data-pool"; size = 1000; }
          ];
          modules = [ ./db-config.nix ];
        };
      });

      # Standard NixOS configurations
      nixosConfigurations = {
        dev-machine = library.makeConfiguration "dev-machine" {
          system = "x86_64-linux";
          modules = [ ./dev-config.nix ];
        };
      };
    };
}
```

## Next Steps

- [Modules Documentation](modules/README.md) - Learn about custom modules
- [Examples](examples.md) - See complete working examples
