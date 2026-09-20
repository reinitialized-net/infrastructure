# Repository Guide

This repository is the NixOS infrastructure flake for the Reinitialized fleet. Treat the checked-in source as the authority for current behavior. Documentation under `docs/investigations/` and dated production-audit files is historical evidence; verify it against source before using it to make changes.

## Start Here

- Check `git status --short` before editing and preserve unrelated user changes.
- Read `flake.nix` plus the host/profile/library files directly involved in the task.
- Use `README.md` and `docs/INDEX.md` to find current repository-specific documentation.
- For live infrastructure work, read `docs/infrastructure-access.md` and use `./tools/infra-access/infra-access` with `tools/infra-access/inventory.json`.
- Never put live secrets in the checkout, including ignored paths. Real secret modules live outside the repository; checked-in templates live in `modules/secrets.example/`.

## Current Shape

`flake.nix` exports these NixOS configurations: `devenv`, `rp1`, `apps1`, `apps2`, `apps3`, `ai1`, and `db1`. VM hosts are also exported as `packages.x86_64-linux.<host>`; `ai1` instead has `packages.x86_64-linux.ai1-installer`. `gs1` exists in source/topology but is not currently exported.

The main repository areas are:

- `flake.nix` — inputs, host exports, validation checks, VMA packages, and the `ai1` installer.
- `library/` — host/configuration/VMA helpers. Normal hosts use `library.makeDualExport`.
- `hosts/` — host-specific configuration and generated-tool definitions.
- `modules/profiles/` — shared NixOS profiles for standard behavior, containers, mesh, firewall, secrets, mounts, and update reporting.
- `modules/secrets.example/` — non-secret templates only.
- `tests/` and `docs/checks/` — repository validation and operational checks.
- `tools/infra-access/` — harness-independent access to authorized infrastructure endpoints.

`library.makeConfiguration` imports `hosts/<name>.nix` automatically. Do not add the host file again to a normal `makeDualExport` `modules` list; use that list only for extra profiles/modules.

## Validation

Prefer the narrowest check that exercises the change.

```bash
# Inspect outputs without modifying flake.lock
nix flake show path:. --no-write-lock-file

# Preferred secret-free source validation for one exported host
nix build path:.#checks.x86_64-linux.<host> --no-write-lock-file --no-link

# Build all current secret-free host checks after shared profile/library changes
nix build \
  path:.#checks.x86_64-linux.devenv \
  path:.#checks.x86_64-linux.rp1 \
  path:.#checks.x86_64-linux.apps1 \
  path:.#checks.x86_64-linux.apps2 \
  path:.#checks.x86_64-linux.apps3 \
  path:.#checks.x86_64-linux.ai1 \
  path:.#checks.x86_64-linux.db1 \
  --no-write-lock-file --no-link

# Build an actual host configuration when external live-secret evaluation is required
INFRA_SECRETS_DIR=/var/lib/infratainer/secrets \
  nix build --impure --no-write-lock-file --no-link \
  path:.#nixosConfigurations.<host>.config.system.build.toplevel

# Build an affected VMA only when image generation itself matters
nix build path:.#packages.x86_64-linux.<host>

# Build the physical ai1 installer when installer behavior changes
nix build path:.#packages.x86_64-linux.ai1-installer
```

Other focused checks:

- `jq empty renovate.json` for Renovate edits.
- `nixfmt-rfc-style <file>.nix` for changed Nix files when available.
- `bash -n <script>` only for raw shell files that parse before Nix placeholder substitution.
- Build/evaluate `devenv` or the relevant host for generated scripts containing Nix-time placeholders.
- Run the relevant Python test directly for changes under `tests/`, `docs/checks/`, or profile-specific test directories.

A successful build is source/build evidence only. Do not describe it as deployment, activation, or matching-hardware runtime verification.

## Repository Patterns

- Define normal hosts with `library.makeDualExport`; keep hostnames, flake exports, mesh topology, secret templates, docs, and ports aligned.
- `modules/profiles/standard.nix` is included by `makeConfiguration`; avoid duplicating its base SSH, sudo, networking, Nix, or user defaults in host files.
- Use systemd-networkd patterns already present in the repository.
- Prefer `networking.firewall.allowlist` and `networking.firewall.denylist` for source-scoped firewall rules.
- Declarative containers use the Docker `backend` network unless the existing host configuration establishes another pattern.
- Scripts under `*/tools/*.sh` may contain `@package@` or computed placeholders. Add substitutions in the sibling Nix tool module rather than hard-coding store paths.
- Stateful service/image changes require checking data compatibility, mounts, backups, and the relevant investigation/architecture docs before editing.

## Secrets And Security

- Never print, commit, copy, or move live credentials into the repository.
- `modules/secrets/` and `result/` are ignored, but ignored files can still enter `path:` flake snapshots. Do not use the checkout as secret storage.
- Use `INFRA_SECRETS_DIR` only when an actual external secret overlay is required. Pure `checks.x86_64-linux.<host>` use checked-in synthetic metadata and must never be deployed.
- Public WireGuard keys belong in `modules/profiles/meshNetwork/meshTopology.nix`; private keys belong in external secret material.
- Preserve SSH, sudo, firewall, OIDC, migration, release, update, and token-validation safeguards. Do not weaken them to make a build pass.
- Treat generated VMA credentials and infrastructure-access credential files as sensitive.

## Deployment And Live Operations

Repository edits do not imply deployment. Deploy, release, tag, push, update `flake.lock`, or build full VMA images only when the task requires it or the user asks.

On `devenv`, the supported fleet tools are:

```bash
rebuildHost <host>
rebuildHost <host> --boot
updateInfra
releaseInfra vMAJOR.MINOR.PATCH --dry-run
```

Do not run remote `rebuildHost` or `updateInfra` with `sudo`; the tools use the invoking user's SSH identity. `rebuildHost devenv` handles its local privilege escalation internally.

For non-fleet devices and direct live checks, use `./tools/infra-access/infra-access`. Inventory reachability is not proof of authentication or write permission. Keep Tailscale exclusions and credential boundaries from `docs/infrastructure-access.md` intact, and validate live changes with the smallest reversible check that proves the intended behavior.

## Working Style

- Fix root causes and keep changes as small as the task allows.
- Preserve intended functionality and existing safety boundaries.
- Prefer source and observed runtime evidence over assumptions from old docs.
- When behavior changes, update the closest current documentation and examples; do not add another one-off prompt, workflow, or model-specific investigation file.
- Report what was changed, what was actually validated, and any remaining runtime/deployment gap.
