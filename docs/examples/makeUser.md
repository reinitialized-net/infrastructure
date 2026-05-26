# Using `makeUser`

`library/makeUser.nix` creates a NixOS module for a user whose home is backed by `/mnt/data`. Current host files import it directly.

Use it when a service or human user needs persistent data on the secondary data disk and should have ownership and permissions created declaratively.

## Requirements

- `/mnt/data` must be configured, usually by importing `modules/profiles/mountData.nix`.
- The VM must have the intended data disk at QEMU `scsi1` if using `mountData`.

The generated module asserts that `/mnt/data` exists in `config.fileSystems`.

## Basic User

```nix
{
  self,
  pkgs,
  ...
}: {
  imports = [
    "${self}/modules/profiles/mountData.nix"

    (import "${self}/library/makeUser.nix" {
      username = "myapp";
      uid = 1001;
      homePermissions = "0700";
      extraUserAttrs = {
        shell = pkgs.bashInteractive;
      };
    })
  ];
}
```

This creates:

- user `myapp`
- group `myapp`
- backing directory `/mnt/data/myapp`
- bind mount `/home/myapp` -> `/mnt/data/myapp`
- tmpfiles rule for permissions and ownership

## Service User Already On `/mnt/data`

When `homeDirectory` and `dataPath` are the same, no bind mount is generated.

```nix
{
  self,
  pkgs,
  ...
}: {
  imports = [
    (import "${self}/library/makeUser.nix" {
      username = "openclaw";
      group = "openclaw";
      homeDirectory = "/mnt/data/openclaw";
      dataPath = "/mnt/data/openclaw";
      homePermissions = "0755";
      extraUserAttrs = {
        isSystemUser = true;
        description = "OpenClaw service user";
        shell = "${pkgs.bash}/bin/bash";
      };
    })
  ];
}
```

This is the pattern used by `hosts/ai1.nix`.

## Multiple Groups

`group` can be a list. The first value is the primary group; the rest are added to `extraGroups`.

```nix
(import "${self}/library/makeUser.nix" {
  username = "builder";
  group = [ "builders" "docker" ];
  extraGroups = [ "wheel" ];
  extraUserAttrs = {
    isNormalUser = true;
  };
})
```

The final extra groups are `docker` and `wheel`.

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `username` | required | User name |
| `uid` | `null` | Optional UID |
| `group` | `username` | Primary group string, or group list |
| `extraGroups` | `[]` | Additional groups |
| `gid` | `null` | Optional primary group GID |
| `homePermissions` | `"0700"` | Mode for `dataPath` |
| `homeDirectory` | `"/home/${username}"` | User home |
| `dataPath` | `"/mnt/data/${username}"` | Backing storage |
| `extraUserAttrs` | `{}` | Merged into `users.users.<username>` |
| `extraGroupAttrs` | `{}` | Merged into the primary `users.groups.<group>` |

If neither `isSystemUser` nor `isNormalUser` is supplied in `extraUserAttrs`, the function defaults to `isNormalUser = true`.

## Troubleshooting

Check that the backing filesystem is mounted:

```bash
mountpoint /mnt/data
```

Check the generated bind mount:

```bash
mount | grep /home/myapp
```

Re-run tmpfiles rules:

```bash
sudo systemctl restart systemd-tmpfiles-setup.service
```

Check ownership:

```bash
ls -ld /mnt/data/myapp /home/myapp
```

## See Also

- [Library Functions](../library-functions.md#librarymakeusernix)
- [Mount Data Profile](../modules/mountData.md)
