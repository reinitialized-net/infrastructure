# GPG "No pinentry" Error on Key Generation

**Date**: 2026-02-08  
**Host**: devenv  
**Issue**: GPG key generation fails with "gpg: agent_genkey failed: No pinentry" error

## Symptoms

When attempting to generate a GPG key interactively using `gpg --gen-key` or similar commands, the process fails with:

```
gpg: agent_genkey failed: No pinentry
Key generation failed: No pinentry
```

## Root Cause

The issue was caused by a missing dependency in the system PATH. While NixOS configuration included:

```nix
programs.gnupg.agent = {
  enable = true;
  pinentryPackage = pkgs.pinentry-curses;
};
```

This configuration sets up the system-wide GPG agent with the appropriate pinentry binary in `/etc/gnupg/gpg-agent.conf`, but **it does not add pinentry to the system PATH**. 

The GPG agent, when running in user context (via systemd user service), cannot locate the pinentry program because:

1. The systemd service's PATH environment variable does not include the pinentry binary location
2. The GPG agent falls back to searching PATH for "pinentry" when the configured pinentry-program fails or is not accessible
3. Users without pinentry in their PATH experience the "No pinentry" error

## Investigation Steps

1. Verified system-wide GPG agent configuration exists:
   ```bash
   $ cat /etc/gnupg/gpg-agent.conf
   pinentry-program /nix/store/8f3jkzd3m2axjz190xdw7v272zadlpbs-pinentry-curses-1.3.2/bin/pinentry
   ```

2. Confirmed pinentry binary exists at the configured path:
   ```bash
   $ ls -la /nix/store/.../pinentry-curses-1.3.2/bin/pinentry
   lrwxrwxrwx ... pinentry -> pinentry-curses
   ```

3. Discovered pinentry is not in PATH:
   ```bash
   $ which pinentry
   which: no pinentry in (...)
   ```

4. Checked systemd user service configuration and found PATH does not include pinentry

## Solution

Add `pinentry-curses` to `environment.systemPackages` in the host configuration:

```nix
environment.systemPackages = with pkgs; [
  # ... other packages ...
  
  # GPG tools - pinentry must be in PATH for GPG agent
  pinentry-curses
];
```

This ensures pinentry is available system-wide at `/run/current-system/sw/bin/pinentry`, making it accessible to all users and processes including the GPG agent.

## Verification

After applying the fix and rebuilding:

```bash
$ which pinentry
/run/current-system/sw/bin/pinentry

$ gpg --batch --generate-key <batch-config>
# Successfully generates key without errors
```

## Why This Works

Adding pinentry to `environment.systemPackages`:

1. Creates a symlink in `/run/current-system/sw/bin/` which is in the default system PATH
2. Makes pinentry available to all users and services
3. Allows the GPG agent to find pinentry even if the hardcoded Nix store path in `/etc/gnupg/gpg-agent.conf` becomes stale
4. Provides a stable, version-independent path for pinentry

## Alternative Approaches (Not Recommended)

1. **User-level gpg-agent.conf with hardcoded path**: Creating `~/.gnupg/gpg-agent.conf` with a hardcoded Nix store path works temporarily but breaks when packages are updated
2. **Home Manager configuration**: Would work but adds complexity and dependencies not needed for this infrastructure
3. **Environment variables**: Setting GPG-specific environment variables is fragile and doesn't propagate to all contexts

## Related Configuration

- Host: [`hosts/devenv.nix`](../../hosts/devenv.nix)
- Module: NixOS built-in `programs.gnupg.agent`
- Documentation: See `man gpg-agent` for pinentry configuration details
