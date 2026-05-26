# Agent Guide

## Scope

This file applies to the whole repository. No nested `AGENTS.md` files currently exist.

## Project Purpose

NixOS infrastructure flake for building Proxmox VMA images and managing the Reinitialized fleet. It defines reusable NixOS modules, host configs, WireGuard mesh networking, Docker-based services, secrets wiring, and devenv-only deployment tools.

## High-Value Commands

```bash
# Show current flake outputs without changing flake.lock
nix flake show path:. --no-write-lock-file

# Fastest useful validation for one host config
nix build path:.#nixosConfigurations.<host>.config.system.build.toplevel

# Build a Proxmox VMA image for one exported host
nix build path:.#packages.x86_64-linux.<host>

# Deploy one host from the devenv machine only
rebuildHost <host>
rebuildHost <host> --boot

# Deploy all mesh-topology hosts from the devenv machine only
updateInfra
```

Exported hosts from `flake.nix`: `devenv`, `rp1`, `apps1`, `apps2`, `apps3`, `ai1`, `db1`.

## Tech Stack

- Nix flakes and NixOS modules.
- Proxmox VMA generation through `library/generateVMAImage/` and `overrides/vma.nix`.
- WireGuard mesh networking, systemd-networkd, nftables firewall rules.
- Docker/OCI containers managed declaratively through NixOS.
- Bash tools generated into host packages with Nix-time placeholder substitution.
- VS Code/Nix tooling: `.vscode/settings.json` enables `nixd` and sets formatting to `nixfmt`; `hosts/devenv.nix` installs `nixfmt-rfc-style`.

## Directory Map

- `flake.nix` - flake inputs, host dual exports, `nixosConfigurations`, VMA packages.
- `flake.lock` - pinned inputs; do not update unless asked or required.
- `library/` - reusable Nix helpers. `makeDualExport` is the primary host-definition API.
- `library/generateVMAImage/` - Proxmox VMA image builder and QEMU config generation.
- `hosts/` - host-specific NixOS configs. `hosts/devenv/tools/` contains fleet management scripts.
- `modules/profiles/` - standard, containers, mesh, firewall, mount data, and secrets profiles.
- `modules/packages/` - custom package overrides for service hosts.
- `modules/secrets.example/` - checked-in secret templates.
- `modules/secrets/` - live secrets, gitignored.
- `docs/` - architecture, module, example, and investigation notes.
- `.agents/workflows/` - workflow snippets for build, deploy, and host creation.
- `.github/copilot-instructions.md` - older agent guidance; verify against current repo files before trusting it.

## Setup And Install

- There is no `devShell`, package manifest, Docker Compose setup, or devcontainer in repo files.
- Required local tool is Nix with flakes enabled. The NixOS standard profile also sets `nix.settings.experimental-features = [ "nix-command" "flakes" ];`.
- On the `devenv` host, repo-specific tools are installed by `hosts/devenv.nix`: `rebuildHost`, `updateInfra`, `updateNetworkFirewallRules`, `nixd`, and `nixfmt-rfc-style`.
- Unknown from repo files: non-Nix workstation bootstrap steps.

## Build, Test, Lint, Format

Use NixOS configuration builds as the primary test. VMA builds are slower because they generate disk images.

```bash
# Single-host config validation
nix build path:.#nixosConfigurations.rp1.config.system.build.toplevel

# Broad exported-host validation without VMA image generation
nix build \
  path:.#nixosConfigurations.devenv.config.system.build.toplevel \
  path:.#nixosConfigurations.rp1.config.system.build.toplevel \
  path:.#nixosConfigurations.apps1.config.system.build.toplevel \
  path:.#nixosConfigurations.apps2.config.system.build.toplevel \
  path:.#nixosConfigurations.apps3.config.system.build.toplevel \
  path:.#nixosConfigurations.ai1.config.system.build.toplevel \
  path:.#nixosConfigurations.db1.config.system.build.toplevel

# Build one VMA package only when needed
nix build path:.#packages.x86_64-linux.rp1

# Format changed Nix files when the formatter is available
nixfmt-rfc-style <file>.nix
```

- No `checks`, `formatter`, `apps`, `devShells`, CI workflow, shellcheck config, shfmt config, or test directory was found.
- Do not assume `nix fmt` works here; no flake `formatter` output is defined.
- For shell scripts with only package-path placeholders, `bash -n <script>` is useful. Scripts with computed block placeholders such as `@hostIpCases@` will not parse before Nix substitution; validate those by building/evaluating the host that generates them.

## Local Run And Deployment

There is no local application server to run. This repo is applied by building and deploying NixOS systems.

```bash
# devenv-only fleet tools
rebuildHost apps1
rebuildHost rp1 --boot
updateInfra

# Manual remote rebuild shape from repo docs/scripts
nixos-rebuild switch --flake path:.#<host> --target-host rnetadmin@<ip> --sudo
```

- `rebuildHost` and `updateInfra` are intended to run on `devenv`.
- Do not run `rebuildHost <remote>` or `updateInfra` with `sudo`; scripts explicitly reject root because SSH key auth breaks. `rebuildHost devenv` uses sudo internally for local activation.
- `updateNetworkFirewallRules --dry-run` is the safest first pass for the OPNsense rule generator.

## Coding Style And Patterns

- Define new hosts with `library.makeDualExport` in `flake.nix`; do not call `makeConfiguration` or `generateVMAImage` directly for normal host additions.
- Add both outputs for new exported hosts: `nixosConfigurations.<name>` and `packages.<system>.<name>`.
- `modules/profiles/standard.nix` is auto-included by `makeConfiguration`; avoid duplicating base SSH, sudo-rs, networking, Nix, or user defaults in host files.
- Prefer existing Nix patterns: `lib.mkDefault` for overridable defaults, `lib.mkForce` only when the repo already enforces a value intentionally.
- Host networking uses systemd-networkd, not NetworkManager. Existing hosts match the primary NIC with `matchConfig.Path = "pci-0000:06:12.0";`.
- Use `networking.firewall.allowlist` and `networking.firewall.denylist` for source-scoped firewall changes instead of broad `allowedTCPPorts` unless the host already uses that pattern.
- Scripts under `*/tools/*.sh` use `@package@` or computed placeholders. Add substitutions in the sibling `*Tools.nix` module rather than hard-coding store paths.
- Keep hostnames, mesh topology keys, secrets filenames, and flake export names aligned.

## Testing Expectations

- For a host-only change, build that host's `config.system.build.toplevel`.
- For shared library or profile changes, build every exported host's toplevel.
- For VMA image generation changes, build at least one affected `packages.x86_64-linux.<host>` output.
- For deployment-tool changes, run `bash -n` where raw templates parse and build or dry-run `devenv` to ensure substitutions still evaluate.
- There are no conventional unit tests in repo files.

## Environment And Secrets

- Do not commit secrets. `.gitignore` excludes `modules/secrets` and `result`.
- Real secrets live in `modules/secrets/<host>.nix`; examples live in `modules/secrets.example/<host>.nix`.
- `makeConfiguration` imports `modules/secrets/<host>.nix` automatically when the file exists.
- When adding or renaming a secret key used by a host, update the matching example file in `modules/secrets.example/`.
- ACME DNS-01 credentials are wired through `config.secrets.acmeDns.file`.
- Docker volume migration uses `config.secrets.volumeMigration.file`.
- `updateNetworkFirewallRules` reads OPNsense config from `secrets.opnsenseFirewall` or these environment variables:

```bash
OPNSENSE_HOST
OPNSENSE_API_KEY
OPNSENSE_API_SECRET
OPNSENSE_PORT
OPNSENSE_VERIFY_TLS
LOG_DAYS
TOP_FLOWS
```

## Database, Migration, And Codegen

- PostgreSQL and Valkey run as Docker containers on `db1`.
- No repo-level migration, seed, schema generation, or codegen command was found.
- Existing investigation docs note service-specific manual migration risks; read relevant docs before changing PostgreSQL images, volume mounts, or application database settings.

## Security Rules

- Never weaken SSH settings, sudo-rs rules, `mutableUsers = false`, firewall scope, OIDC settings, or container validation to make a build pass.
- Never remove validation or guardrails in deployment, Docker migration, firewall, ACME, or mesh tooling without replacing them with an equivalent safeguard.
- Never copy WireGuard private keys into `meshTopology.nix`; topology stores public keys only.
- Treat `result/CREDENTIALS.txt` from VMA builds as sensitive and do not commit it.
- Preserve restricted Docker migration SSH behavior unless explicitly changing the migration design.

## Common Gotchas

- `gs1` exists in `hosts/`, `modules/secrets.example/`, and `meshTopology.nix`, but is currently commented out of `flake.nix` exports. Commands using `.#gs1` will not work until the flake exports it.
- `updateInfra` derives valid hosts from `meshTopology.nix`, not from `nixosConfigurations`; verify exports before fleet-wide deploys.
- README and older agent docs may lag behind `flake.nix`. Trust `flake.nix` and successful `nix flake show` output for current exports.
- `mountData.nix` auto-formats and auto-resizes `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1`; only use it with the intended second disk.
- VMA builds generate random `rnetadmin` credentials into `result/CREDENTIALS.txt`.
- Docker hosts bind `/var/lib/docker` and `/var/lib/docker/volumes` into `/mnt/data/docker`; volume and disk changes can affect persistent service data.
- `rp1` uses Angie/nginx stream and virtual hosts for public ingress. Validate upstream names and ports carefully before deploy.

## Agent Workflow

1. Inspect current files first: `flake.nix`, touched host/profile/library modules, matching docs, and matching `modules/secrets.example/` files.
2. Check `git status --short` and do not overwrite user changes.
3. Make the smallest coherent change. Keep unrelated refactors out.
4. Run the narrowest relevant validation command.
5. If shared behavior changed, run broader NixOS toplevel builds.
6. Do not deploy, update lockfiles, or build full VMAs unless the task requires it or the user asks.

## PR Checklist

- [ ] Current flake exports checked when commands or host names changed.
- [ ] Relevant host/profile/library docs updated without copying long README content.
- [ ] Matching `modules/secrets.example/<host>.nix` updated for any secret key changes.
- [ ] No live secrets, generated `result/`, or credentials committed.
- [ ] Narrow Nix build or syntax check run and result noted.
- [ ] Broader exported-host build run for shared module/library changes, or explicitly skipped with reason.
