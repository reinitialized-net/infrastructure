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
  hardwareClockInLocalTime = lib.mkDefault false;  # Use UTC for RTC to avoid DST issues
};
```

Override in your configuration:

```nix
time.timeZone = "Europe/London";
```

### NTP Time Synchronization

```nix
services.timesyncd = {
  enable = lib.mkDefault true;
  servers = lib.mkDefault [
    "10.1.11.1"
  ];
};
```

- Uses systemd-timesyncd for NTP
- Points to internal NTP server at 10.1.11.1
- Override to use public NTP servers if needed

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
  useDHCP = lib.mkDefault true;
  
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
  isNormalUser = lib.mkForce true;
  createHome = lib.mkDefault true;
  group = lib.mkForce "rnetadmin";
  extraGroups = lib.mkDefault [ "wheel" ];
  shell = lib.mkForce pkgs.bashInteractive;
  
  openssh.authorizedKeys.keys = [ 
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5pCeT2IuImFk0Rc2qcxudr8hVTgWvQDcwkXi0Hybru rnetadmin"
  ];
};
```

- System user with home directory
- Member of wheel group (sudo access)
- SSH key authentication
- Default password (override in production!)

**Important:** When using `makeDualExport` to generate VMA images, a random password is generated and saved to `CREDENTIALS.txt` in the build output.

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

#### polkit

Configures polkit rules for systemd management:

```nix
security.polkit = {
  enable = lib.mkDefault true;
  extraConfig = ''
    polkit.addRule(function(action, subject) {
      if ((action.id == "org.freedesktop.systemd1.manage-units" ||
           action.id == "org.freedesktop.systemd1.manage-unit-files" ||
           action.id == "org.freedesktop.systemd1.reload-daemon") &&
          subject.isInGroup("wheel")) {
        return polkit.Result.YES;
      }
    });
    
    // Allow root user to manage systemd units (needed for sudo + systemd-run)
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          subject.user == "root") {
        return polkit.Result.YES;
      }
    });
  '';
};
```

- Allows wheel group to manage systemd units without authentication
- Required for `nixos-rebuild` with `sudo-rs` over SSH
- Also allows root to manage units (needed for `sudo + systemd-run`)

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

### DBus Reconnect Workaround

A timer-triggered service that recovers from a systemd 258 + NixOS daemon-reexec DBus disconnect issue:

```nix
systemd.services.dbus-reconnect = {
  description = "Recover systemd DBus connection after daemon-reexec";
  after = [ "dbus.service" ];
  serviceConfig = {
    Type = "oneshot";
    ExecCondition = /* script that checks if org.freedesktop.systemd1 is on the bus */;
    ExecStart = /* script that restarts dbus and logind to recover */;
  };
};

systemd.timers.dbus-reconnect = {
  description = "Periodically check for systemd DBus disconnect";
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnBootSec = "30s";
    OnUnitActiveSec = "30s";
    AccuracySec = "5s";
  };
};
```

- **Problem:** When `switch-to-configuration` triggers a daemon-reexec, systemd PID 1 can lose its DBus connection ("Got disconnect on API bus"), causing `systemd-run`/`systemctl` and logind to fail
- **Detection:** Timer runs every 30s, checks if `org.freedesktop.systemd1` is present on the bus
- **Recovery:** If missing, restarts `dbus.service` and `systemd-logind.service` to restore connectivity
- See [nixos-rebuild access denied investigation](../investigations/nixos-rebuild-access-denied.md) for details

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

## Usage

The standard profile is automatically included when using `makeDualExport` (the recommended pattern for all hosts):

```nix
let
  dualSystems = {
    my-vm = library.makeDualExport "my-vm" {
      system = "x86_64-linux";
      vmId = 100;
      # standard profile is automatically included
      modules = [
        {
          networking.hostName = "my-vm";
        }
      ];
    };
  };
in
{
  nixosConfigurations.my-vm = dualSystems.my-vm.nixosSystem;
  packages.x86_64-linux.my-vm = dualSystems.my-vm.package;
}
```

**Note:** Do not use `generateVMAImage` or `makeConfiguration` directly — always use `makeDualExport`.

## See Also

- [Library Functions](../library-functions.md) - Using generateVMAImage and makeConfiguration
- [Examples](../examples.md) - Complete configuration examples
