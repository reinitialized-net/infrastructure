# Automatic Updates

`devenv` coordinates automatic infrastructure updates from a managed checkout under `/var/lib/infratainer`. The user's working tree is not used by scheduled automation.

## Flow

1. `infra-renovate.timer` runs daily at `01:00`.
   It runs Renovate against Forgejo using `RENOVATE_PLATFORM=forgejo`, opens update PRs, and stores logs in `/var/log/infratainer`.
2. `infra-promote.timer` runs daily at `01:45`.
   It inspects open Renovate PRs whose branch starts with `renovate/`.
3. PRs labeled `infra-auto-merge` are validated locally:

   ```bash
   nix flake show path:. --no-write-lock-file
   nix build --no-link \
     path:.#nixosConfigurations.devenv.config.system.build.toplevel \
     path:.#nixosConfigurations.rp1.config.system.build.toplevel \
     path:.#nixosConfigurations.apps1.config.system.build.toplevel \
     path:.#nixosConfigurations.apps2.config.system.build.toplevel \
     path:.#nixosConfigurations.apps3.config.system.build.toplevel \
     path:.#nixosConfigurations.db1.config.system.build.toplevel
   bash -n hosts/devenv/tools/update-network-firewall-rules.sh
   ```

4. Passing PRs are merged through the Forgejo API. Failing PRs receive a comment and create or update a Forgejo issue.
5. `infra-deploy.timer` runs daily at `02:30`, refreshes the managed checkout, and runs:

   ```bash
   FLAKE_PATH=/var/lib/infratainer/checkout updateInfra
   ```

Host-local `nixos-upgrade.timer` remains enabled as a fallback and runs later from the Forgejo flake URL.

## Secrets

`hosts/devenv/infraAutoUpdate.nix` reads `secrets.infraAutomation` for Renovate, promotion, deployment, and failure reporting. Container hosts also use `secrets.infraAutomation` for `docker-container-auto-update.service` failure reports.

The token file defaults to `/run/secrets/infra-automation-token`. On `devenv`, it must be readable by `rnetadmin` because Renovate, promotion, and deployment run as that user. On container hosts, the reporting service runs as root and needs the same token available locally. The token needs Forgejo repository, pull request, and issue read/write access.

The automation identity defaults to `Infratainer`. Set `secrets.infraAutomation.keys.automationName` once for the display/git author name and override `forgejoUsername` only if Forgejo requires a different login string.

Example secret metadata lives in `modules/secrets.example/devenv.nix` and the container-host examples.

## Renovate Labels

`renovate.json` labels eligible PRs with `infra-auto-merge`. The promoter only merges PRs with that label after validation passes.

Major container updates are labeled `manual-update`; they stay open and produce a tracking issue instead of being merged automatically.

## Container Image Updates

The Docker image pull timer remains enabled through `services.containerAutoUpdate`. The containers profile enables the shared `infra-update-report@.service` so Docker auto-update failures can create or update Forgejo issues from the affected host.

High-risk containers are skipped from digest-drift restarts on each host and are instead handled by Renovate PRs. Low-risk containers continue to pull and restart automatically when the image ID changes. The updater logs structured `container_update_event` lines with container name, image, service, old image ID, new image ID, and action.

Check the timers:

```bash
systemctl list-timers infra-renovate.timer infra-promote.timer infra-deploy.timer docker-container-auto-update.timer nixos-upgrade.timer
```

Inspect failures:

```bash
journalctl -u infra-renovate.service
journalctl -u infra-promote.service
journalctl -u infra-deploy.service
journalctl -u docker-container-auto-update.service
```
