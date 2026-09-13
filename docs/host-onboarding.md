# Add a New Host

This workflow covers all the steps required to add a new host to the infrastructure.

## Steps

1. Create the host configuration file at `hosts/<name>.nix`. Use an existing host file as a reference (e.g., `hosts/apps1.nix`).

2. Add a dual export entry in `flake.nix` under the `dualSystems` attribute set:
```nix
<name> = library.makeDualExport "<name>" {
  system = "x86_64-linux";
  vmId = <unique-vm-id>;
  # makeConfiguration imports hosts/<name>.nix automatically.
  modules = [ ]; # Add extra profiles here if needed.
  # Add disks, networking, cores, memory as needed
};
```

3. Export both outputs from the dual export in `flake.nix`:
   - Add to `nixosConfigurations`: `<name> = dualSystems.<name>.nixosSystem;`
   - Add to `packages`: `<name> = dualSystems.<name>.package;`

4. If the host needs secrets, add a non-secret template at `modules/secrets.example/<name>.nix`. Provision its live host module outside the checkout at `/var/lib/infratainer/secrets/<name>.nix`, using quoted runtime file paths. Provision the actual runtime secret files separately on the target host with restrictive ownership and permissions; `/run/secrets` files must be provisioned on every boot. See [Secrets Management](modules/secrets.md). Never create live files under `modules/secrets/` or anywhere else in the checkout: `path:` flake snapshots include gitignored files and copy them into the Nix store.

5. If the host joins the mesh network, add its node definition to `modules/profiles/meshNetwork/meshTopology.nix`.

6. Build and test the new host configuration from a checkout containing no live secrets, with the external host module from step 4:
```bash
INFRA_SECRETS_DIR=/var/lib/infratainer/secrets \
  nix build --impure --no-write-lock-file --no-link \
  .#nixosConfigurations.<name>.config.system.build.toplevel
```

Git flakes include tracked files; stage the new non-secret host, template, and flake changes before evaluating. For a host that needs no secret module, omit `INFRA_SECRETS_DIR` and `--impure`.

## Important Reminders

- **ALWAYS use `makeDualExport`** — never call `generateVMAImage` or `makeConfiguration` directly
- Every VMA export requires a unique `vmId`
- If using `/mnt/data` bind mounts, include `mountData.nix` profile AND configure a second disk
- `mutableUsers = false` — all users must be declared in the configuration
