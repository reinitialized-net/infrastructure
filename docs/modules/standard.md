# Standard Profile

**Module path:** `modules/profiles/standard.nix`

**Import:** Automatically included by `library/makeConfiguration.nix`.

## Overview

The standard profile defines the base NixOS behavior for hosts built through this repository's library functions. It sets time, SSH, users, sudo-rs, nftables, systemd-networkd, Nix settings, automatic system upgrades, and DBus switch/recovery behavior used around some `nixos-rebuild switch` runs.

## Defaults

### Time

```nix
time = {
  timeZone = lib.mkDefault "America/Chicago";
  hardwareClockInLocalTime = lib.mkDefault false;
};

services.timesyncd = {
  enable = lib.mkDefault true;
  servers = lib.mkDefault [ "10.1.11.1" ];
};
```

### Networking And Firewall

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

Host files usually set `networking.useDHCP = false` and define static addresses through `systemd.network.networks`.

### SSH

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

Password and keyboard-interactive SSH auth are disabled. Root SSH login is key-only.

### Base Packages

```nix
environment.systemPackages = with pkgs; [
  bash
  shadow
  vim
];
```

### Users

The profile configures immutable users:

```nix
users = {
  mutableUsers = lib.mkForce false;
  allowNoPasswordLogin = lib.mkForce true;
  defaultUserShell = lib.mkDefault pkgs.bashInteractive;
};
```

It creates:

- `root` with no initial password and Bash shell
- `rnetadmin` as a normal wheel user with an SSH authorized key
- `rnetadmin` group

For VMA builds, `generateVMAImage` overrides `rnetadmin.hashedPassword` with a generated password written to `CREDENTIALS.txt`.

### sudo-rs And Polkit

Traditional sudo is disabled and sudo-rs is enabled:

```nix
security = {
  sudo.enable = lib.mkForce false;
  sudo-rs = {
    enable = lib.mkForce true;
    wheelNeedsPassword = lib.mkDefault false;
  };
};
```

Polkit rules allow wheel users and root to manage systemd units. This supports remote `nixos-rebuild --sudo` flows that use systemd.

### Nix

```nix
nix.settings = {
  auto-optimise-store = lib.mkForce true;
  experimental-features = lib.mkForce [ "nix-command" "flakes" ];
  trusted-users = lib.mkForce [ "rnetadmin" ];
};
```

Only `rnetadmin` is explicitly listed in `trusted-users` by this profile.

### Automatic System Upgrades

```nix
system.autoUpgrade = {
  enable = lib.mkForce true;
  flake = lib.mkDefault "git+https://git.ds.reinitialized.net/reinitialized.net/infrastructure.git?ref=indev";
  flags = lib.mkAfter [ "--impure" ];
  operation = lib.mkDefault "switch";
  dates = lib.mkDefault "05:00";
  randomizedDelaySec = lib.mkDefault "45min";
};
```

This host-local timer is a fallback after the `devenv` coordinated automatic update window. It sets `INFRA_SECRETS_DIR=/var/lib/infratainer/secrets` so clean fetched flakes can import local live secret modules. See [Automatic Updates](../architecture/automatic-updates.md).

Check the timer and service:

```bash
systemctl list-timers nixos-upgrade.timer
systemctl status nixos-upgrade.service
journalctl -u nixos-upgrade.service
```

### DBus Reconnect Timer

The profile prevents the `dbus` and `dbus-broker` system and user units from being reloaded, restarted, or stopped during a NixOS switch. DBus changes are applied on the next boot instead of during live activation.

The profile defines `dbus-reconnect.service` and `dbus-reconnect.timer`. The timer runs shortly after boot and every 30 seconds. If `org.freedesktop.systemd1` is missing from the system bus, the service restarts `dbus.service` and `systemd-logind.service`.

This works around a systemd daemon-reexec issue observed during rebuilds. See [nixos-rebuild access denied investigation](../investigations/nixos-rebuild-access-denied.md).

## Overriding Defaults

Most values use `lib.mkDefault` or `lib.mkForce`. Override `mkDefault` values normally:

```nix
{
  time.timeZone = "Europe/London";
  system.autoUpgrade.dates = "Mon *-*-* 01:00";
  security.sudo-rs.wheelNeedsPassword = true;
}
```

Values set with `mkForce` are intentionally enforced by the profile. Avoid weakening SSH, sudo-rs, mutable-user, or firewall settings to make a build pass.

## Usage

You normally do not import this profile directly. It is included by hosts built through:

```nix
library.makeDualExport "host" { ... }
```

or:

```nix
library.makeConfiguration "host" { ... }
```

It is not part of `nixosModules.default`.

## See Also

- [Library Functions](../library-functions.md)
- [Firewall Module](firewall.md)
- [Profiles Summary](../profiles.md)
