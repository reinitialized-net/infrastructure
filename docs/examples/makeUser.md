# Using makeUser

This guide shows how to use the `makeUser` library function to create users with properly configured home directories on `/mnt/data`.

## Problem

When setting up users with bind-mounted home directories from `/mnt/data`, permissions often get lost or incorrectly set, especially:
- After system reboots
- When the underlying filesystem doesn't preserve ownership
- During initial setup before the user logs in

## Solution

The `makeUser` function handles:
1. User and group creation
2. Directory creation on `/mnt/data` with correct permissions
3. Bind mounting to the home directory location
4. Setting ownership via systemd-tmpfiles (runs before user login)

## Basic Usage

### Single User

```nix
{
  inputs = {
    reinitialized-infra.url = "github:reinitialized-net/infrastructure";
  };

  outputs = { self, reinitialized-infra }:
    let
      library = reinitialized-infra.lib;
      infra = "${reinitialized-infra}";
      
      dualSystems = {
        app-server = library.makeDualExport "app-server" {
          system = "x86_64-linux";
          vmId = 200;
          
          disks = [
            { storage = "hotData"; size = 20; }
            { storage = "coldData"; size = 50; }  # Required for mountData
          ];
          
          modules = [
            # Required: mount data profile
            "${infra}/modules/profiles/mountData.nix"
            
            # Create user with proper home directory
            ((import "${infra}/library/makeUser.nix" {}) {
              username = "myapp";
              uid = 1001;
            })
            
            # Additional configuration
            {
              systemd.services.myapp = {
                description = "My Application";
                wantedBy = [ "multi-user.target" ];
                serviceConfig = {
                  User = "myapp";
                  WorkingDirectory = "/home/myapp";
                  ExecStart = "/home/myapp/app";
                };
              };
            }
          ];
        };
      };
    in
    {
      nixosConfigurations.app-server = dualSystems.app-server.nixosSystem;
      packages.x86_64-linux.app-server = dualSystems.app-server.package;
    };
}
```

### Multiple Users

```nix
{
  modules = [
    "${inputs.self}/modules/profiles/mountData.nix"
    
    # Web application user
    ((import "${inputs.self}/library/makeUser.nix" {}) {
      username = "webapp";
      uid = 1001;
      group = "webapps";
      gid = 1001;
      extraUserAttrs = {
        extraGroups = [ "docker" ];
        shell = pkgs.bashInteractive;
      };
    })
    
    # API user
    ((import "${inputs.self}/library/makeUser.nix" {}) {
      username = "api";
      uid = 1002;
      group = "webapps";
      extraUserAttrs = {
        extraGroups = [ "docker" ];
        shell = pkgs.bashInteractive;
      };
    })
    
    # Database user with custom home
    ((import "${inputs.self}/library/makeUser.nix" {}) {
      username = "postgres";
      uid = 1003;
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

## Advanced Examples

### Developer User with SSH Keys

```nix
(library.makeUser {
  username = "developer";
  uid = 1000;
  homePermissions = "0700";
  extraUserAttrs = {
    extraGroups = [ "wheel" "docker" ];
    shell = pkgs.bashInteractive;
    initialHashedPassword = "$6$rounds=656000$...";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... developer@laptop"
    ];
  };
})
```

### Service User with Restrictive Permissions

```nix
(library.makeUser {
  username = "myservice";
  uid = 2001;
  group = "services";
  gid = 2000;
  homeDirectory = "/opt/myservice";
  dataPath = "/mnt/data/services/myservice";
  homePermissions = "0750";  # Owner: rwx, Group: rx
  extraUserAttrs = {
    isSystemUser = true;
    shell = pkgs.bash;
  };
})
```

### Shared Group Setup

```nix
{
  imports = [
    "${reinitialized-infra.inputs.self}/modules/profiles/mountData.nix"
    
    # Multiple users in same group with shared permissions
    (library.makeUser {
      username = "app1";
      uid = 3001;
      group = "appgroup";
      gid = 3000;
      homePermissions = "0770";  # Owner and group: rwx
    })
    
    (library.makeUser {
      username = "app2";
      uid = 3002;
      group = "appgroup";
      homePermissions = "0770";
    })
  ];
  
  # Ensure the group exists
  users.groups.appgroup.gid = 3000;
}
```

## Permission Guide

Common permission settings:

- `"0700"` - Owner only (default, most secure for user homes)
- `"0750"` - Owner full, group read/execute
- `"0770"` - Owner and group full access
- `"0755"` - Owner full, others read/execute
- `"0775"` - Owner and group full, others read/execute

## Troubleshooting

### Permission Denied After Reboot

**Symptom**: User can't access their home directory after system restart.

**Cause**: The tmpfiles rules didn't run or the bind mount failed.

**Solution**:
```bash
# Check if tmpfiles ran
systemctl status systemd-tmpfiles-setup.service

# Manually trigger tmpfiles
systemctl restart systemd-tmpfiles-setup.service

# Check mount
mount | grep /home/username

# Verify permissions
ls -ld /mnt/data/username
```

### Wrong Ownership

**Symptom**: Directory exists but has root:root ownership.

**Cause**: User was created after tmpfiles ran.

**Solution**:
```bash
# Manually fix ownership
chown -R username:group /mnt/data/username

# Or restart tmpfiles
systemctl restart systemd-tmpfiles-setup.service
```

### Mount Fails

**Symptom**: Home directory is empty or mount point doesn't exist.

**Cause**: `/mnt/data` is not mounted or dependency issue.

**Solution**:
```bash
# Check if /mnt/data is mounted
mount | grep /mnt/data

# Check for errors
journalctl -u local-fs.target

# Verify the source exists
ls -ld /mnt/data/username
```

## Migration from Manual Setup

If you have existing users with manual bind mounts, migrate like this:

### Before (Manual):

```nix
{
  fileSystems."/home/myapp" = {
    device = "/mnt/data/myapp";
    depends = [ "/mnt/data" ];
    fsType = "none";
    options = [ "bind" ];
  };
  
  users.users.myapp = {
    isNormalUser = true;
    home = "/home/myapp";
    uid = 1001;
  };
  
  # Maybe permissions are set manually via script or forgotten
}
```

### After (Using Function):

```nix
{
  imports = [
    (library.makeUser {
      username = "myapp";
      uid = 1001;
      homePermissions = "0700";
    })
  ];
}
```

The function automatically handles:
- ✅ User creation
- ✅ Group creation
- ✅ Directory creation with correct permissions
- ✅ Ownership setup via tmpfiles
- ✅ Bind mount configuration
- ✅ Mount dependencies

## Best Practices

1. **Always specify UIDs/GIDs** for production systems to ensure consistency
2. **Use restrictive permissions** (0700) unless there's a specific need for sharing
3. **Test after reboot** to ensure permissions persist
4. **Document custom paths** if not using defaults
5. **Group related users** under common groups when they need to share data

## See Also

- [mountData Profile](profiles.md#mountdata) - Required for this function
- [Standard Profile](profiles.md#standard) - Default user configuration
- [Library Functions](library-functions.md) - All available functions
