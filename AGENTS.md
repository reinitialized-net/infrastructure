# Agent Guide

## Scope

This file applies to the whole repository. No nested `AGENTS.md` files currently exist.

## Project Purpose

NixOS infrastructure flake for the Reinitialized fleet. It builds Proxmox VMA images, exports live NixOS configurations for rebuilds, and defines reusable profiles for WireGuard mesh networking, Docker services, secrets wiring, firewall rules, and fleet automation.

## High-Value Commands

```bash
# Show current flake outputs without changing flake.lock
nix flake show path:. --no-write-lock-file

# Fastest useful validation for one host config
nix build path:.#nixosConfigurations.<host>.config.system.build.toplevel

# Broad validation without VMA image generation
nix build \
  path:.#nixosConfigurations.devenv.config.system.build.toplevel \
  path:.#nixosConfigurations.rp1.config.system.build.toplevel \
  path:.#nixosConfigurations.apps1.config.system.build.toplevel \
  path:.#nixosConfigurations.apps2.config.system.build.toplevel \
  path:.#nixosConfigurations.apps3.config.system.build.toplevel \
  path:.#nixosConfigurations.db1.config.system.build.toplevel

# Build one Proxmox VMA image
nix build path:.#packages.x86_64-linux.<host>

# Devenv-only deployment tools
rebuildHost <host>
rebuildHost <host> --boot
updateInfra

# Devenv-only release helper
releaseInfra vMAJOR.MINOR.PATCH --dry-run
releaseInfra vMAJOR.MINOR.PATCH
```

Exported hosts from `flake.nix`: `devenv`, `rp1`, `apps1`, `apps2`, `apps3`, `db1`.

## Tech Stack

- Nix flakes and NixOS modules pinned by `flake.lock`.
- Proxmox VMA generation through `library/generateVMAImage/` and `overrides/vma.nix`.
- WireGuard mesh networking on `wg-mesh`, systemd-networkd, nftables firewall rules.
- Docker/OCI containers managed declaratively through NixOS.
- Bash tools generated into host packages with Nix-time placeholder substitution.
- Renovate plus Forgejo automation for dependency PRs, validation, promotion, and deploy from `devenv`.
- VS Code/Nix tooling: `.vscode/settings.json` enables `nixd` and asks for `nixfmt`; `hosts/devenv.nix` installs `nixfmt-rfc-style`.

## Directory Map

- `flake.nix` - flake inputs, `makeDualExport` host definitions, `nixosConfigurations`, VMA packages.
- `flake.lock` - pinned flake inputs; do not update unless asked or required.
- `renovate.json` - Renovate config for Nix inputs and Docker image tags.
- `CHANGELOG.md` - release notes required by `releaseInfra`.
- `library/` - reusable Nix helpers. `makeDualExport` is the normal host-definition API.
- `library/generateVMAImage/` - Proxmox VMA image builder and QEMU config generation.
- `hosts/` - host-specific NixOS configs.
- `hosts/devenv/tools/` - generated fleet scripts: `rebuildHost`, `updateInfra`, `releaseInfra`, `updateNetworkFirewallRules`.
- `hosts/devenv/infraAutoUpdate.nix` - Infratainer/Renovate promotion and deploy timers on `devenv`.
- `modules/profiles/` - standard, containers, mesh, firewall, mount data, secrets, and update-report profiles.
- `modules/packages/` - custom package overrides for service hosts.
- `modules/secrets.example/` - checked-in secret templates.
- `modules/secrets/` - live secrets, gitignored.
- `docs/` - architecture, module, example, release, and investigation notes.
- `.agents/workflows/` - workflow snippets; verify against source before trusting them.
- `.vscode/` - editor recommendations and Nix language-server settings.

## Setup And Install

- Required local tool is Nix with flakes enabled. The standard profile sets `nix.settings.experimental-features = [ "nix-command" "flakes" ];`.
- There is no `devShell`, package manifest, Docker Compose setup, devcontainer, or CI workflow in repo files.
- This flake does not define `checks`, `formatter`, `apps`, or `devShells`.
- On `devenv`, repo tools are installed by NixOS modules: `rebuildHost`, `updateInfra`, `releaseInfra`, `updateNetworkFirewallRules`, `infra-renovate`, `infra-promote`, `infra-deploy`, `nixd`, and `nixfmt-rfc-style`.
- Unknown from repo files: non-Nix workstation bootstrap steps.

## Build, Test, Lint, Format

Use NixOS toplevel builds as the primary validation. VMA builds are slower because they generate disk images.

```bash
# Single-host config validation
nix build path:.#nixosConfigurations.rp1.config.system.build.toplevel

# Build one VMA package only when needed
nix build path:.#packages.x86_64-linux.rp1

# Validate Renovate config
jq empty renovate.json

# Syntax-check raw scripts that parse before Nix substitution
bash -n hosts/devenv/tools/update-network-firewall-rules.sh
bash -n hosts/devenv/tools/release-infra.sh

# Format changed Nix files when the formatter is available
nixfmt-rfc-style <file>.nix
```

- Do not assume `nix fmt` or `nix flake check` is the validation path; no flake `formatter` or `checks` output exists.
- For shell scripts with computed block placeholders such as `@hostIpCases@`, raw `bash -n` will not parse before Nix substitution. Validate by building/evaluating the host that generates them.
- For automatic-update validation against external live secrets, use `INFRA_SECRETS_DIR=/path/to/secrets` with `--impure`.
- There is no conventional unit test directory in repo files.

## Local Run, Deployment, And Releases

There is no local app server. This repo is applied by building and deploying NixOS systems.

```bash
# Devenv-only fleet tools
rebuildHost apps1
rebuildHost rp1 --boot
updateInfra

# Skip one or more hosts during fleet deploy
UPDATE_INFRA_SKIP_HOSTS="devenv apps3" updateInfra

# Use a non-default checkout or external live secret overlay
FLAKE_PATH=/var/lib/infratainer/checkout INFRA_SECRETS_DIR=/var/lib/infratainer/secrets updateInfra

# Manual release flow on clean indev checkout
releaseInfra v0.1.0 --dry-run
releaseInfra v0.1.0
releaseInfra v0.1.0 --push
```

- `rebuildHost` and `updateInfra` are intended to run on `devenv`.
- Do not run `rebuildHost <remote>` or `updateInfra` with `sudo`; scripts reject root because SSH key auth breaks. `rebuildHost devenv` uses sudo internally for local activation.
- `updateInfra` targets flake-exported hosts that also exist in `meshTopology.nix`, unless `UPDATE_INFRA_SKIP_HOSTS` excludes them.
- `updateNetworkFirewallRules --dry-run` is the safest first pass for the OPNsense rule generator.
- `releaseInfra` requires a clean `indev` checkout, a matching `CHANGELOG.md` heading, no existing local/remote tag, `jq empty renovate.json`, `nix flake show`, all deployable host toplevel builds with `--no-link`, and script syntax checks.

## Automatic Updates

- `devenv` runs Infratainer from a managed checkout under `/var/lib/infratainer`; scheduled automation does not use a normal working tree.
- Timers from `hosts/devenv/infraAutoUpdate.nix`: `infra-renovate.timer` at `01:00`, `infra-promote.timer` at `01:45`, `infra-deploy.timer` at `02:30`.
- Run the flow manually through systemd units, not by invoking generated binaries from an arbitrary shell user:

```bash
sudo systemctl start infra-renovate.service
sudo systemctl start infra-promote.service
sudo systemctl start infra-deploy.service
systemctl list-timers infra-renovate.timer infra-promote.timer infra-deploy.timer docker-container-auto-update.timer nixos-upgrade.timer
journalctl -u infra-renovate.service
journalctl -u infra-promote.service
journalctl -u infra-deploy.service
```

- Renovate tracks `indev`. PRs labeled `infra-auto-merge` are locally validated and merged; `manual-update` PRs require a current human approval before promotion.
- Host-local `nixos-upgrade.timer` remains enabled as a fallback and uses `INFRA_SECRETS_DIR=/var/lib/infratainer/secrets` with `--impure`.

## Coding Style And Patterns

- Define normal hosts with `library.makeDualExport` in `flake.nix`; do not call `makeConfiguration` or `generateVMAImage` directly for normal host additions.
- Add both outputs for new exported hosts: `nixosConfigurations.<name>` and `packages.<system>.<name>`.
- `makeConfiguration` auto-imports `hosts/<name>.nix`; use the `modules` argument to `makeDualExport` only for extra profiles/modules such as `containers` or `mountData`.
- `modules/profiles/standard.nix` is auto-included by `makeConfiguration`; avoid duplicating base SSH, sudo-rs, networking, Nix, or user defaults in host files.
- Prefer existing Nix patterns: `lib.mkDefault` for overridable defaults, `lib.mkForce` only when the repo already enforces a value intentionally.
- Host networking uses systemd-networkd, not NetworkManager. Current hosts match the primary NIC with `matchConfig.Path = "pci-0000:06:12.0";`.
- Use `networking.firewall.allowlist` and `networking.firewall.denylist` for source-scoped firewall changes instead of broad `allowedTCPPorts`, unless the host already uses that pattern.
- Declarative containers attach to the Docker mesh with `networks = [ "backend" ];`.
- Scripts under `*/tools/*.sh` use `@package@` or computed placeholders. Add substitutions in the sibling `*Tools.nix` module rather than hard-coding store paths.
- Keep hostnames, mesh topology keys, secrets filenames, flake export names, docs, and port references aligned.
- For release-policy changes, update `CHANGELOG.md`, `docs/release-process.md`, and `renovate.json` only when the source behavior changes.

## Testing Expectations

- Host-only change: build that host's `config.system.build.toplevel`.
- Shared library/profile change: build every exported host's toplevel.
- VMA generation change: build at least one affected `packages.x86_64-linux.<host>` output.
- Deployment-tool change: run `bash -n` where raw templates parse and build `devenv` or a relevant host so substitutions evaluate.
- Secret-key change: update the matching `modules/secrets.example/<host>.nix` and build a host that consumes it.
- Renovate/release automation change: run `jq empty renovate.json`, relevant script syntax checks, and the narrowest Nix build that exercises the changed module.
- Full `releaseInfra ... --dry-run` is useful only on a clean `indev` checkout.

## Environment And Secrets

- Do not commit secrets. `.gitignore` excludes `modules/secrets` and `result`.
- Real secrets live in `modules/secrets/<host>.nix`; examples live in `modules/secrets.example/<host>.nix`.
- `makeConfiguration` imports `modules/secrets/<host>.nix` automatically when present. If `INFRA_SECRETS_DIR` is set, it can import `$INFRA_SECRETS_DIR/<host>.nix` during impure evaluation; if the file is missing there, evaluation throws.
- When adding or renaming a secret key used by a host, update the matching example file in `modules/secrets.example/`.
- `secrets.meshNetwork.file` stores the WireGuard private key. Public keys belong in `modules/profiles/meshNetwork/meshTopology.nix`.
- ACME DNS-01 credentials are wired through `config.secrets.acmeDns.file`.
- Docker volume migration uses `config.secrets.volumeMigration.file`.
- Infratainer uses `secrets.infraAutomation`; the token file defaults to `/run/secrets/infra-automation-token` and must not point into `/nix/store`.
- `updateNetworkFirewallRules` reads OPNsense config from `secrets.opnsenseFirewall` or these environment variables:

```bash
OPNSENSE_HOST
OPNSENSE_API_KEY
OPNSENSE_API_SECRET
OPNSENSE_PORT
OPNSENSE_VERIFY_TLS
LOG_DAYS
TOP_FLOWS
API_CONNECT_TIMEOUT
API_MAX_TIMEOUT
```

Other tool environment variables visible in source:

```bash
FLAKE_PATH
INFRA_SECRETS_DIR
UPDATE_INFRA_SKIP_HOSTS
```

## Database, Migration, And Codegen

- PostgreSQL 18 with pgvector and Valkey run as Docker containers on `db1`.
- No repo-level app database migration, seed, schema generation, or codegen command was found.
- `migrate-volumes` is available on container hosts for Docker volume export/import/transfer; it is operational data movement, not an application migration framework.
- Existing investigation docs note service-specific manual migration risks. Read relevant docs before changing PostgreSQL images, volume mounts, database paths, or stateful container images.

## Security Rules

- Never weaken SSH settings, sudo-rs rules, `mutableUsers = false`, firewall scope, OIDC settings, Infratainer token checks, or container validation to make a build pass.
- Never remove validation or guardrails in deployment, release, Docker migration, firewall, ACME, automatic update, or mesh tooling without replacing them with an equivalent safeguard.
- Never copy WireGuard private keys into `meshTopology.nix`; topology stores public keys only.
- Treat `result/CREDENTIALS.txt` from VMA builds as sensitive and do not commit it.
- Preserve restricted Docker migration SSH behavior unless explicitly changing the migration design.
- Treat `/run/secrets/infra-automation-token`, `/var/lib/infratainer/secrets`, and `modules/secrets/infra-automation-token` as sensitive token material.

## Common Gotchas

- `gs1` exists in `hosts/`, `modules/secrets.example/`, and `meshTopology.nix`, but is commented out of `flake.nix` exports. Commands using `.#gs1` will not work until the flake exports it.
- `updateInfra` deploys hosts that are both exported from `flake.nix` and present in `meshTopology.nix`.
- Docs and `.agents` workflow snippets may lag behind `flake.nix`; trust source files and successful flake output for current exports.
- `.agents/workflows/add-host.md` shows adding `./hosts/<name>.nix` in `modules`; current `makeConfiguration` auto-imports host files, so do not duplicate that import.
- `mesh-keygen` currently prints a stale `modules/secrets/mesh.nix` path; current host secrets belong in `modules/secrets/<host>.nix`.
- `.vscode/settings.json` references `nixfmt`, while repository docs and `devenv` packages use `nixfmt-rfc-style`.
- `mountData.nix` auto-formats and auto-resizes `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1`; only use it with the intended second disk.
- VMA builds generate random `rnetadmin` credentials into `result/CREDENTIALS.txt`.
- Docker hosts bind `/var/lib/docker` and `/var/lib/docker/volumes` into `/mnt/data/docker`; volume and disk changes can affect persistent service data.
- `rp1` uses Angie/nginx stream and virtual hosts for public ingress. Validate upstream names, bind addresses, SNI routing, and ports carefully before deploy.
- Stateful datastore image updates are labeled `manual-update` in `renovate.json`; review data compatibility and backup requirements before merging.

## Agent Workflow

1. Inspect current files first: `flake.nix`, touched host/profile/library modules, matching docs, matching examples, and matching `modules/secrets.example/` files.
2. Check `git status --short` and do not overwrite user changes.
3. Make the smallest coherent change. Keep unrelated refactors out.
4. Run the narrowest relevant validation command.
5. If shared behavior changed, run broader NixOS toplevel builds.
6. Do not deploy, update lockfiles, tag releases, push, or build full VMAs unless the task requires it or the user asks.

## PR Checklist

- [ ] Current flake exports checked when commands or host names changed.
- [ ] Relevant host/profile/library docs updated without copying long README content.
- [ ] Matching `modules/secrets.example/<host>.nix` updated for any secret key changes.
- [ ] `CHANGELOG.md`, `docs/release-process.md`, or `renovate.json` updated when release or dependency automation behavior changed.
- [ ] No live secrets, generated `result/`, tokens, or credentials committed.
- [ ] Narrow Nix build or syntax check run and result noted.
- [ ] Broader exported-host build run for shared module/library changes, or explicitly skipped with reason.
