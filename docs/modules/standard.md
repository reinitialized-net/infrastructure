# Standard Profile

**Module Path:** `modules/profiles/standard.nix`

**Import:** Automatically included in all configurations created with library functions

## Overview

The standard profile provides a base configuration for all NixOS systems in this infrastructure. It configures essential system services, security settings, and tools that every system should have.

## Features

- SSH server with secure defaults
- sudo-rs (Rust sudo implementation)
- Automatic system updates from GitHub
- Basic system utilities
- Standardized user setup
- Firewall with nftables
- systemd-networkd networking

## What It Configures

### Time Zone

```nix
time = {
  timeZone = lib.mkDefault "America/Chicago";
  hardwareClockInLocalTime = lib.mkDefault true;
};
```

Override in your configuration:

```nix
time.timeZone = "Europe/London";
```

### Networking

- **NetworkManager**: Disabled (uses systemd-networkd instead)
- **systemd-networkd**: Enabled for modern network management
- **nftables**: Enabled as firewall backend
- **Firewall**: Enabled by default

```nix
networking = {
  hostName = lib.mkDefault "nixos-qemu";
  nftables.enable = lib.mkDefault true;
  networkmanager.enable = lib.mkForce false;
  useNetworkd = lib.mkForce true;
  useDHCP = lib.mkDefault false;
  
  firewall = {
    enable = lib.mkForce true;
    package = lib.mkForce pkgs.nftables;
  };
};
```

### SSH Server

Secure SSH configuration:

```nix
services.openssh = {
  enable = lib.mkForce true;
  settings = {
    PermitRootLogin = lib.mkForce "prohibit-password";
    PasswordAuthentication = lib.mkForce false;
    KbdInteractiveAuthentication = lib.mkForce false;
  };
};
```

- Root login via SSH keys only
- Password authentication disabled
- Keyboard-interactive authentication disabled

### System Packages

Essential utilities:

```nix
environment.systemPackages = with pkgs; [
  bash
  shadow
  vim
];
```

### Users

#### Root User

```nix
users.users.root = {
  initialHashedPassword = lib.mkForce null;
  shell = lib.mkForce pkgs.bashInteractive;
};
```

- No password (SSH key only)
- Bash shell

#### rnetadmin User

Default administrative user:

```nix
users.users.rnetadmin = {
  initialHashedPassword = lib.mkDefault "$6$ELaXwtqP5R5l.n5e$...";
  isSystemUser = lib.mkForce true;
  createHome = lib.mkForce true;
  group = lib.mkForce "rnetadmin";
  extraGroups = lib.mkDefault [ "wheel" ];
  shell = lib.mkForce pkgs.bashInteractive;
  
  openssh.authorizedKeys.keys = lib.mkDefault [ 
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5pCeT2IuImFk0Rc2qcxudr8hVTgWvQDcwkXi0Hybru rnetadmin"
  ];
};
```

- System user with home directory
- Member of wheel group (sudo access)
- SSH key authentication
- Default password (override in production!)

**Important:** When using `generateVMAImage`, a random password is generated and saved to `CREDENTIALS.txt` in the build output.

### User System Configuration

```nix
users = {
  mutableUsers = lib.mkForce false;
  allowNoPasswordLogin = lib.mkForce true;
  defaultUserShell = lib.mkDefault pkgs.bashInteractive;
};
```

- Immutable users (managed via configuration only)
- No-password login allowed (for console access)
- Bash as default shell

### Security

#### sudo-rs

Uses the Rust implementation of sudo:

```nix
security = {
  sudo.enable = lib.mkForce false;
  sudo-rs = {
    enable = lib.mkForce true;
    wheelNeedsPassword = lib.mkDefault false;
  };
};
```

- More secure than traditional sudo
- wheel group doesn't need password by default

#### Nix Settings

```nix
nix.settings = {
  auto-optimise-store = lib.mkForce true;
  experimental-features = lib.mkForce [ "nix-command" "flakes" ];
  trusted-users = lib.mkForce [ "root" "rnetadmin" ];
};
```

- Automatic store optimization
- Flakes enabled
- Trusted users for nix commands

### Automatic Updates

```nix
system.autoUpgrade = {
  enable = lib.mkForce true;
  flake = lib.mkDefault "github:reinitialized.net/infrastructure";
  dates = lib.mkDefault "02:00";
  randomizedDelaySec = lib.mkDefault "45min";
};
```

- Daily updates at 2:00 AM (±45 minutes)
- Pulls from GitHub repository
- Keeps systems up to date automatically

## Customization

### Override Defaults

All settings use `lib.mkDefault`, so you can override them:

```nix
{
  # Change timezone
  time.timeZone = "Europe/Paris";
  
  # Change hostname
  networking.hostName = "my-server";
  
  # Disable auto-updates
  system.autoUpgrade.enable = false;
  
  # Require password for sudo
  security.sudo-rs.wheelNeedsPassword = true;
  
  # Add more packages
  environment.systemPackages = with pkgs; [
    git
    htop
    tmux
  ];
}
```

### Add Users

```nix
{
  users.users.developer = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAA... developer@workstation"
    ];
  };
}
```

### Change Auto-Update Source

```nix
{
  system.autoUpgrade = {
    flake = "github:myorg/infrastructure";
    dates = "weekly";  # Instead of daily
  };
}
```

### Disable Auto-Updates

```nix
{
  system.autoUpgrade.enable = false;
}
```

## Security Considerations

1. **Change Default Passwords**: The default `rnetadmin` password should be changed
2. **Add SSH Keys**: Configure your own SSH keys
3. **Review sudo Settings**: Consider requiring password for sudo in production
4. **Firewall Rules**: Configure appropriate firewall rules for your services
5. **Auto-Updates**: Ensure the update source is trusted

## Usage in VM Images

The standard profile is automatically included when using `generateVMAImage`:

```nix
{
  packages.x86_64-linux.my-vm = generateVMAImage "my-vm" {
    vmId = 100;
    # standard profile is automatically included
    
    modules = [
      {
        # Your additional configuration
        networking.hostName = "my-vm";
      }
    ];
  };
}
```

## Usage in Regular Configurations

Also included when using `makeConfiguration`:

```nix
{
  nixosConfigurations.my-host = makeConfiguration "my-host" {
    modules = [
      {
        # Your configuration
      }
    ];
  };
}
```

## See Also

- [Library Functions](../library-functions.md) - Using generateVMAImage and makeConfiguration
- [Examples](../examples.md) - Complete configuration examples
