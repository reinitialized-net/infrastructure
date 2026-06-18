---
description: Deploy configuration changes to all hosts in the fleet using updateInfra
---

# Deploy to All Hosts

This workflow deploys NixOS configuration changes to ALL hosts in the fleet using the `updateInfra` fleet management tool (available on devenv only).

## Steps

1. Run the fleet-wide update:
```bash
updateInfra
```

2. Monitor the output for progress and summary of successful/failed hosts.

## Notes

- Deploys to all hosts exported from `flake.nix` that also have mesh topology
- Builds on devenv and deploys to remote targets via SSH
- Uses `rnetadmin` user for remote connections
- This can take significant time as it rebuilds every host sequentially
