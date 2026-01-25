# Library Functions

This flake provides library functions for building NixOS configurations and Proxmox VM images.

## Available Functions

- **[`makeDualExport`](#makedualexport)** - Export both VMA package and nixosSystem from single definition (PRIMARY)
- **[`makeUser`](#makeuser)** - Create user with bind-mounted home from /mnt/data
- **[`forAllSystems`](#forallsystems)** - Apply function to all supported architectures
- **[`generateVMAImage`](#generatevmaimage)** - Generate Proxmox VMA images (internal, use via makeDualExport)
- **[`makeConfiguration`](#makeconfiguration)** - Create nixosSystem (internal, use via makeDualExport)

---

### `makeDualExport`

**PRIMARY FUNCTION** - Creates both a VMA package and nixosSystem from a single definition. This is the recommended way to define systems in this infrastructure.

#### Signature

```nix
makeDualExport :: String -> AttrSet -> { package :: Derivation; nixosSystem :: AttrSet; }
```

#### Purpose

Eliminates duplication by allowing you to define a system once and export both:
- A Proxmox VMA image package for deployment
- A nixosSystem configuration for testing and rebuilding

#### Parameters

**`host`** (String, required)
- The hostname for the system
- Used in VM configuration and as the system hostname

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
- NixOS modules to include
- Default: `[]`

**VMA-Specific Options:**

**`vmId`** (Integer, required for VMA)
- Unique Proxmox VM ID
- Required when `exportVMA = true`

**`cores`** (Integer, optional)
- CPU cores
- Default: `2`

**`memory`** (Integer, optional)
- RAM in megabytes
- Default: `4096`

**`enableProtection`** (Boolean, optional)
- Proxmox VM protection
- Default: `true`

**`disks`** (List of AttrSet, optional)
- Disk configuration
- Default: Single 25GB disk on `"hotData"`
- Each disk: `{ storage = "name"; size = GB; }`

**`networking`** (List of AttrSet, optional)
- Network interfaces
- Default: Single interface on vmbr0, VLAN 200, DHCP
- Each interface: `{ bridge = "name"; firewall = bool; vlan = int; }`

**Export Control:**

**`exportVMA`** (Boolean, optional)
- Whether to export VMA package
- Default: `true`

**`exportNixOS`** (Boolean, optional)
- Whether to export nixosSystem
- Default: `true`

#### Return Value

Returns an attribute set with:
- **`package`** - VMA image derivation (if `exportVMA = true`)
- **`nixosSystem`** - NixOS system configuration (if `exportNixOS = true`)

#### Example Usage

##### Basic Dual Export

```nix
# In flake.nix
{
  outputs = { self, ... }:
    let
      library = import ./library { inherit self; };
      
      dualSystems = {
        myhost = library.makeDualExport "myhost" {
          system = "x86_64-linux";
          vmId = 100;
          modules = [ ./hosts/myhost.nix ];
        };
      };
    in
    {
      # Export both outputs
      nixosConfigurations.myhost = dualSystems.myhost.nixosSystem;
      packages.x86_64-linux.myhost = dualSystems.myhost.package;
    };
}
```

##### Advanced Configuration

```nix
{
  outputs = { self, ... }:
    let
      library = import ./library { inherit self; };
      
      dualSystems = {
        appserver = library.makeDualExport "appserver" {
          system = "x86_64-linux";
          vmId = 150;
          
          # Resources
          cores = 8;
          memory = 16384;
          enableProtection = true;
          
          # Multiple disks
          disks = [
            { storage = "fast-ssd"; size = 50; }
            { storage = "bulk-storage"; size = 500; }
          ];
          
          # Multiple networks
          networking = [
            { bridge = "vmbr0"; vlan = 100; firewall = true; }
            { bridge = "vmbr1"; vlan = 200; firewall = false; }
          ];
          
          # Custom modules
          modules = [
            ./modules/profiles/containers
            ./hosts/appserver.nix
          ];
        };
      };
    in
    {
      nixosConfigurations.appserver = dualSystems.appserver.nixosSystem;
      packages.x86_64-linux.appserver = dualSystems.appserver.package;
    };
}
```

#### Usage Patterns

**Building VMA Image:**
```bash
nix build path:.#packages.x86_64-linux.myhost
ls result/
# vzdump-qemu-100.vma.zst
# CREDENTIALS.txt
```

**Testing Configuration:**
```bash
# Build without deploying
nix build path:.#nixosConfigurations.myhost.config.system.build.toplevel

# Deploy to live system
nixos-rebuild switch --flake path:.#myhost --target-host user@myhost
```

**Remote Deployment:**
```bash
nixos-rebuild switch \
  --flake path:.#myhost \
  --target-host rnetadmin@10.1.11.2 \
  --build-host rnetadmin@10.1.200.2 \
  --use-remote-sudo
```

---

### `makeUser`

Creates a user with their home directory bind-mounted from `/mnt/data`. Handles proper permissions and ensures `/mnt/data` is mounted first.

#### Signature

```nix
makeUser :: AttrSet -> Module
```

#### Parameters

**`username`** (String, required)
- The username to create

**`uid`** (Integer, optional)
- User ID
- Default: auto-assigned

**`group`** (String, optional)
- Primary group name
- Default: same as username

**`gid`** (Integer, optional)
- Group ID
- Default: auto-assigned

**`homePermissions`** (String, optional)
- Home directory permissions
- Default: `"0700"`

**`homeDirectory`** (String, optional)
- Home directory path
- Default: `"/home/${username}"`

**`dataPath`** (String, optional)
- Path under /mnt/data
- Default: `"/mnt/data/${username}"`

**`extraUserAttrs`** (AttrSet, optional)
- Additional user attributes
- Default: `{}`

**`extraGroupAttrs`** (AttrSet, optional)
- Additional group attributes
- Default: `{}`

#### Example Usage

##### Basic User

```nix
{
  imports = [
    ./modules/profiles/mountData.nix
    ((import ./library/makeUser.nix {}) {
      username = "myapp";
      uid = 1001;
    })
  ];
}
```

##### User with Extra Attributes

```nix
{
  imports = [
    ((import ./library/makeUser.nix {}) {
      username = "develop";
      group = "developers";
      homePermissions = "0750";
      extraUserAttrs = {
        extraGroups = [ "docker" "wheel" ];
        shell = pkgs.bashInteractive;
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAA..."
        ];
      };
    })
  ];
}
```

#### Requirements

- `modules/profiles/mountData.nix` must be imported (enforced by assertion)
- Second disk must be configured in VMA disks array

---

### `forAllSystems`

Helper for applying a function across all supported architectures.

#### Signature

```nix
forAllSystems :: (String -> a) -> AttrSet
```

#### Supported Systems

- `x86_64-linux`
- `aarch64-linux`

#### Example Usage

```nix
{
  packages = library.forAllSystems (system: {
    mypackage = /* build for system */;
  });
}
```

---

### `generateVMAImage`

**INTERNAL FUNCTION** - Used by `makeDualExport`. Direct use is not recommended.

Generates a Proxmox-compatible VMA (Vzdump) format VM image with a complete NixOS system.

**Recommendation:** Use `makeDualExport` instead for new systems.

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
   - Includes timestamp of when credentials were generated
   - **IMPORTANT**: Save this password securely before deleting the file
   - Format:
     ```
     VM ID: 150
     Hostname: app-server
     Username: rnetadmin
     Password: <randomly-generated-32-char-password>
     
     Generated: 2026-01-22 11:30:45 UTC
     ```

#### Building the Image

```bash
# Build the image
nix build path:.#packages.x86_64-linux.app-server

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
nixos-rebuild build --flake path:.#webserver

# Or activate directly
nixos-rebuild switch --flake path:.#webserver
```

---

### `makeDualExport`

Creates both a Proxmox VMA package and a NixOS system configuration from a single system definition. This eliminates duplication when you need to maintain both a VMA image (for deployment) and a nixosSystem (for development/testing).

#### Signature

```nix
makeDualExport :: String -> AttrSet -> { package, nixosSystem }
```

#### Parameters

**`host`** (String, required)
- The hostname for the system
- Used in both the VMA and nixosSystem configurations
- Example: `"devenv"`

**Configuration AttrSet:**

All parameters from `generateVMAImage` are supported, plus:

**`exportVMA`** (Boolean, optional)
- Whether to export the VMA package
- Default: `true`
- Set to `false` if you only need nixosSystem

**`exportNixOS`** (Boolean, optional)
- Whether to export the nixosSystem
- Default: `true`
- Set to `false` if you only need VMA package

#### Return Value

Returns an attribute set with:
- **`package`**: The VMA image derivation (for use in `packages`)
- **`nixosSystem`**: The NixOS configuration (for use in `nixosConfigurations`)

#### Example Usage

```nix
{
  outputs = { self, ... }:
    let
      library = import ./library { inherit self; };
      
      # Define dual-export systems once
      dualSystems = {
        devenv = library.makeDualExport "devenv" {
          system = "x86_64-linux";
          vmId = 203;
          cores = 4;
          memory = 8192;
          disks = [
            { storage = "hotData"; size = 20; }
            { storage = "coldData"; size = 100; }
          ];
          networking = [
            { bridge = "vmbr0"; firewall = false; vlan = 200; useDHCP = true; }
          ];
          modules = [
            ./devenv-config.nix
          ];
        };
      };
    in
    {
      # Reference nixosSystem from dual export
      nixosConfigurations = {
        devenv = dualSystems.devenv.nixosSystem;
      };

      # Reference VMA package from dual export
      packages = library.forAllSystems (system: {
        devenv = dualSystems.devenv.package;
      });
    };
}
```

#### Benefits

- **Single Source of Truth**: Define your system configuration once
- **No Duplication**: Avoid maintaining separate VMA and nixosSystem configs
- **Consistent Behavior**: Both outputs use the same modules and settings
- **Flexible**: Can export both or just one, depending on needs

#### Use Cases

1. **Development VMs**: Build VMA for Proxmox, use nixosSystem for `nixos-rebuild test`
2. **Testing**: Test configuration changes with nixosSystem before building VMA
3. **CI/CD**: Build both artifacts from single config definition
4. **Documentation**: Maintain one configuration that serves multiple purposes

---

### `makeUser`

Creates a user with their home directory bind-mounted from `/mnt/data` and ensures proper permissions are set via systemd-tmpfiles.

This function handles:
- User and group creation with specified attributes
- Bind mounting home directory from `/mnt/data`
- Setting correct ownership and permissions automatically
- Dependencies to ensure `/mnt/data` is mounted first

#### Signature

```nix
makeUser :: AttrSet -> Module
```

#### Parameters

**`username`** (String, required)
- The username to create
- Example: `"myapp"`

**`uid`** (Integer, optional)
- Optional UID for the user
- If not specified, NixOS will assign automatically
- Example: `1001`

**`group`** (String, optional)
- Group name for the user
- Default: Same as username
- Example: `"myapp"`

**`gid`** (Integer, optional)
- Optional GID for the group
- If not specified, NixOS will assign automatically
- Example: `1001`

**`homePermissions`** (String, optional)
- Permissions for the home directory
- Default: `"0700"` (owner read/write/execute only)
- Example: `"0750"` (owner rwx, group rx)

**`homeDirectory`** (String, optional)
- Custom home directory path
- Default: `/home/${username}`
- Example: `"/opt/myapp"`

**`dataPath`** (String, optional)
- Path under `/mnt/data` for the actual storage
- Default: `/mnt/data/${username}`
- Example: `"/mnt/data/applications/myapp"`

**`extraUserAttrs`** (AttrSet, optional)
- Additional attributes to pass to `users.users.<name>`
- Can include: `extraGroups`, `shell`, `openssh.authorizedKeys`, etc.
- Default: `{}`
- Example: `{ extraGroups = [ "docker" ]; shell = pkgs.bashInteractive; }`

**`extraGroupAttrs`** (AttrSet, optional)
- Additional attributes to pass to `users.groups.<name>`
- Default: `{}`

#### Returns

A NixOS module that configures:
- User account
- Group (if doesn't exist)
- systemd-tmpfiles rules for directory creation and permissions
- Bind mount from `/mnt/data` to home directory
- Assertion to ensure `/mnt/data` is configured

#### Requirements

- The system must have `/mnt/data` configured (use `modules/profiles/mountData.nix`)
- The function is used as an import in your configuration

#### Example Usage

**Basic user:**

```nix
{
  inputs = {
    reinitialized-infra.url = "github:reinitialized-net/infrastructure";
  };

  outputs = { self, reinitialized-infra }:
    let
      library = reinitialized-infra.lib;
    in
    {
      packages.x86_64-linux.app-server = library.generateVMAImage "app-server" {
        system = "x86_64-linux";
        vmId = 200;
        
        modules = [
          "${reinitialized-infra.inputs.self}/modules/profiles/mountData.nix"
          
          # Create user with data home
          (library.makeUser {
            username = "myapp";
            uid = 1001;
            homePermissions = "0700";
          })
        ];
      };
    };
}
```

**User with custom attributes:**

```nix
imports = [
  (library.makeUser {
    username = "webapp";
    uid = 1002;
    group = "webapps";
    gid = 1002;
    homeDirectory = "/opt/webapp";
    dataPath = "/mnt/data/applications/webapp";
    homePermissions = "0750";
    extraUserAttrs = {
      extraGroups = [ "docker" "nginx" ];
      shell = pkgs.bashInteractive;
      initialHashedPassword = "$6$...";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAA... webapp@example.com"
      ];
    };
  })
];
```

**Multiple users:**

```nix
{
  modules = [
    "${reinitialized-infra.inputs.self}/modules/profiles/mountData.nix"
    
    # Application user
    (library.makeUser {
      username = "api";
      uid = 1001;
    })
    
    # Database user
    (library.makeUser {
      username = "postgres";
      uid = 1002;
      homeDirectory = "/var/lib/postgresql";
      dataPath = "/mnt/data/postgres";
      homePermissions = "0700";
      extraUserAttrs = {
        isSystemUser = true;
      };
    })
  ];
}
```

#### How It Works

1. **Directory Creation**: systemd-tmpfiles creates `/mnt/data/${username}` with specified permissions during boot
2. **Ownership**: The directory is owned by the specified user and group
3. **Bind Mount**: The directory is bind-mounted to the home directory location
4. **Mount Dependencies**: The bind mount depends on `/mnt/data` being mounted first
5. **Assertions**: Validates that `/mnt/data` is configured before proceeding

This ensures proper permissions even if the `/mnt/data` directory is on a filesystem that doesn't preserve permissions well (like some shared storage systems).

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
