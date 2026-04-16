# OpenClaw User Service DBUS Error Investigation

**Date**: April 15, 2026  
**Host**: ai1 (10.1.11.9)  
**Service**: openclaw-gateway  
**Issue**: `Failed to connect to user scope bus via local transport: $DBUS_SESSION_BUS_ADDRESS and $XDG_RUNTIME_DIR not defined`

## Problem Description

When trying to check the status of the `openclaw-gateway` user service via SSH:
```bash
[openclaw@ai1:~]$ systemctl status --user openclaw-gateway
Failed to connect to user scope bus via local transport: $DBUS_SESSION_BUS_ADDRESS and $XDG_RUNTIME_DIR not defined (consider using --machine=<user>@.host --user to connect to bus of other user)
```

## Root Cause Analysis

### 1. User Service vs System Service
- **User Service**: Created by openclaw application at `/var/lib/openclaw/.config/systemd/user/openclaw-gateway.service`
- **System Service**: Defined in Nix configuration at `hosts/ai1.nix` as `systemd.services.openclaw`

The error occurred because:
1. The `openclaw` user doesn't have an active login session when accessed via SSH
2. Systemd user services require an active user session with proper environment variables (`DBUS_SESSION_BUS_ADDRESS`, `XDG_RUNTIME_DIR`)
3. SSH sessions don't automatically create systemd user sessions

### 2. Configuration Issues
The original system service configuration had several problems:
1. **Invalid command syntax**: Using `--allow-origins` option which doesn't exist in openclaw 2026.4.11
2. **Missing `--allow-unconfigured`**: Required to run without a config file
3. **CORS issues with `--bind lan`**: Non-loopback binding requires CORS configuration
4. **Port conflicts**: Old processes were still running on port 18789

## Solution Implemented

### 1. Enable Lingering for openclaw User
```bash
sudo loginctl enable-linger openclaw
```
This allows user services to run without an active login session.

### 2. Fix System Service Configuration
Updated `hosts/ai1.nix` with correct command:
```nix
systemd.services.openclaw = {
  description = "OpenClaw AI Assistant Gateway";
  after = [ "network.target" ];
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    User = "openclaw";
    Group = "openclaw";
    WorkingDirectory = "/mnt/data/openclaw";
    Environment = [
      "OPENCLAW_NIX_MODE=1"
      "OPENCLAW_STATE_DIR=/mnt/data/openclaw"
    ];
    ExecStart = "${pkgsUnstable.openclaw}/bin/openclaw gateway --port 18789 --bind loopback --allow-unconfigured";
    Restart = "always";
  };
};
```

**Key changes:**
- Removed invalid `--allow-origins` option
- Added `--allow-unconfigured` to run without config file
- Changed to `--bind loopback` to avoid CORS issues
- Removed reference to invalid config file

### 3. Clean Up Old Processes
Killed old `openclaw-gateway` processes that were holding port 18789:
```bash
sudo kill -9 <pid>
sudo systemctl restart openclaw
```

## Best Practices Established

### 1. Use System Services for Daemons
- **System services** are preferred for long-running daemons
- Better integration with NixOS configuration management
- No session dependency issues

### 2. Proper Command Syntax
- Use `gateway --port <port>` not `gateway run --port <port>`
- Include `--allow-unconfigured` when running without config
- Use `--bind loopback` for local-only services to avoid CORS

### 3. Check for Port Conflicts
- Always check if port is already in use: `ss -tlnp | grep :<port>`
- Kill old processes before restarting services

### 4. Managing User Services (If Needed)
If user services must be checked:
```bash
# With lingering enabled
sudo -u openclaw bash -c 'export XDG_RUNTIME_DIR=/run/user/$(id -u openclaw) && export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus && systemctl --user status <service>'

# Or use machine syntax
systemctl --machine=openclaw@.host --user status <service>
```

## Verification

After fixes:
- ✅ System service `openclaw.service` is running
- ✅ Listening on port 18789 (loopback only)
- ✅ No CORS errors
- ✅ "gateway ready" message in logs
- ✅ Running in Nix mode (config managed externally)

## Files Modified
- `hosts/ai1.nix` - Fixed system service configuration

## Related Documentation
- [Systemd User Services](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html#User%20Units)
- [OpenClaw CLI Reference](https://docs.openclaw.ai/cli/gateway)
- [NixOS Systemd Module](https://nixos.org/manual/nixos/stable/index.html#sec-systemd)