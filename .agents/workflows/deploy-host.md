---
description: Deploy configuration changes to a single host using rebuildHost
---

# Deploy a Single Host

This workflow deploys NixOS configuration changes to a single host using the `rebuildHost` fleet management tool (available on devenv only).

## Steps

1. Identify the target host name from the hosts table (devenv, rp1, apps1, apps2, apps3, db1).

2. Deploy to the target host (builds on devenv, deploys to target via SSH):
```bash
rebuildHost <hostname>
```

3. If you want changes to activate on next reboot instead of immediately, use the `--boot` flag:
```bash
rebuildHost <hostname> --boot
```

4. For local devenv deployment:
```bash
rebuildHost devenv
```

## Notes

- `rebuildHost` auto-resolves host IPs from `meshTopology.nix`
- Builds happen on devenv and deploy to remote targets via SSH
- Uses `rnetadmin` user for remote connections
- Displays progress and summary of successful/failed deployments
