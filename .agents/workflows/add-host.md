---
description: Add a new host to the NixOS infrastructure
---

# Add a New Host

This workflow covers all the steps required to add a new host to the infrastructure.

## Steps

1. Create the host configuration file at `hosts/<name>.nix`. Use an existing host file as a reference (e.g., `hosts/apps1.nix`).

2. Add a dual export entry in `flake.nix` under the `dualSystems` attribute set:
```nix
<name> = library.makeDualExport "<name>" {
  system = "x86_64-linux";
  vmId = <unique-vm-id>;
  modules = [ ./hosts/<name>.nix ];
  # Add disks, networking, cores, memory as needed
};
```

3. Export both outputs from the dual export in `flake.nix`:
   - Add to `nixosConfigurations`: `<name> = dualSystems.<name>.nixosSystem;`
   - Add to `packages`: `<name> = dualSystems.<name>.package;`

4. If the host needs secrets, create a secrets file at `modules/secrets/<name>.nix` with a corresponding example at `modules/secrets.example/<name>.nix`.

5. If the host joins the mesh network, add its node definition to `modules/profiles/meshNetwork/meshTopology.nix`.

6. Build and test the new host configuration:
```bash
nix build path:.#nixosConfigurations.<name>.config.system.build.toplevel
```

## Important Reminders

- **ALWAYS use `makeDualExport`** — never call `generateVMAImage` or `makeConfiguration` directly
- Every VMA export requires a unique `vmId`
- If using `/mnt/data` bind mounts, include `mountData.nix` profile AND configure a second disk
- `mutableUsers = false` — all users must be declared in the configuration
