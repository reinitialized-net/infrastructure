# Automatic Updates

`devenv` coordinates automatic infrastructure updates from a managed checkout under `/var/lib/infratainer`. The user's working tree is not used by scheduled automation. Repository automation tracks the `indev` branch.

## Flow

1. `infra-renovate.timer` runs daily at `01:00`.
   It runs Renovate against Forgejo using `RENOVATE_PLATFORM=forgejo`, opens update PRs against `indev`, and stores logs in `/var/log/infratainer`.
   Dependency Dashboard checkbox clicks are also handled by `infra-renovate-dashboard-webhook.service`. Forgejo persists the checkbox as an issue-body edit; the webhook starts `infra-renovate.service` so Renovate consumes the checked box immediately instead of waiting for the next daily timer.
2. `infra-promote.timer` runs daily at `01:45`.
   It inspects open Renovate PRs whose branch starts with `renovate/`.
3. PRs labeled `infra-auto-merge` are validated locally. PRs labeled `manual-update`
   are left open until they have a current approving PR review from someone other
   than the Infratainer automation account, then they use the same validation path:

   ```bash
   INFRA_SECRETS_DIR=/var/lib/infratainer/secrets nix flake show path:. --no-write-lock-file --impure
   INFRA_SECRETS_DIR=/var/lib/infratainer/secrets nix build --impure --no-link \
     path:.#nixosConfigurations.devenv.config.system.build.toplevel \
     path:.#nixosConfigurations.rp1.config.system.build.toplevel \
     path:.#nixosConfigurations.apps1.config.system.build.toplevel \
     path:.#nixosConfigurations.apps2.config.system.build.toplevel \
     path:.#nixosConfigurations.apps3.config.system.build.toplevel \
     path:.#nixosConfigurations.db1.config.system.build.toplevel
   bash -n hosts/devenv/tools/update-network-firewall-rules.sh
   ```

4. Passing PRs are merged into `indev` through the Forgejo API. Failing PRs receive a comment and create or update a Forgejo issue.
5. `infra-deploy.timer` runs daily at `02:30`, refreshes the managed checkout to `origin/indev`, and runs:

   ```bash
   INFRA_SECRETS_DIR=/var/lib/infratainer/secrets FLAKE_PATH=/var/lib/infratainer/checkout updateInfra
   ```

Host-local `nixos-upgrade.timer` remains enabled as a fallback and runs later from the Forgejo flake URL with `?ref=indev`. It passes `--impure` and `INFRA_SECRETS_DIR=/var/lib/infratainer/secrets` so the fetched clean flake can import host-local live secret modules.

## Secrets

`hosts/devenv/infraAutoUpdate.nix` reads `secrets.infraAutomation` for Renovate, promotion, deployment, and failure reporting. Container hosts also use `secrets.infraAutomation` for `docker-container-auto-update.service` failure reports.

The token file defaults to `/run/secrets/infra-automation-token`. On `devenv`, it must be readable by `rnetadmin` because Renovate, promotion, and deployment run as that user. On container hosts, the reporting service runs as root and needs the same token available locally. The token needs Forgejo repository, pull request, and issue read/write access. Do not point `secrets.infraAutomation.file` at a relative file in `modules/secrets`; `devenv` rejects Nix store token paths so the generated automation does not read bearer tokens from the store.

The automation identity defaults to `Infratainer`. Set `secrets.infraAutomation.keys.automationName` once for the display/git author name and override `forgejoUsername` only if Forgejo requires a different login string.

Example secret metadata lives in `modules/secrets.example/devenv.nix` and the container-host examples.

Set `secrets.infraAutomation.keys.defaultBranch = "indev"` if overriding the default branch in live secrets.

Set `secrets.infraAutomation.keys.secretsDir` if the automation secret overlay should live somewhere other than `/var/lib/infratainer/secrets`.

Set `secrets.infraAutomation.keys.githubTokenFile` on `devenv` when Renovate should fetch release notes from public GitHub repositories. The file should contain a GitHub token with read-only public repository/API access and no write scopes. The service exports it as `GITHUB_COM_TOKEN` for Renovate only when the file is configured and readable. Omit this key if GitHub release-note lookup is intentionally disabled for the deployment.

Immediate Dependency Dashboard checkbox handling is enabled by default on `devenv`. Override `secrets.infraAutomation.keys.dashboardWebhookEnabled = false` only when the deployment should rely on the daily timer. The listener binds only to the WireGuard mesh address `10.255.0.1:1044`, validates Forgejo/Gitea/GitHub-style HMAC signatures, ignores Infratainer-authored dashboard rewrites, and starts only `infra-renovate.service`.

`secrets.infraAutomation.keys.dashboardWebhookSecretFile` defaults to `/run/secrets/infra-renovate-webhook-secret`. During activation, `devenv` restores that file from `/var/lib/infratainer/secrets/infra-renovate-webhook-secret`; if neither copy exists, activation generates a new random secret and stores it persistently outside the repository. `infra-renovate-dashboard-webhook-ensure.service` then creates or updates the Forgejo repository webhook with that secret through the existing Infratainer Forgejo token.

The managed checkout does not contain `modules/secrets/` because those files are gitignored. During `devenv` activation, if the local flake source contains the live `modules/secrets` tree, activation copies `*.nix` secret modules into the external secrets directory and seeds `modules/secrets/infra-automation-token` as `/var/lib/infratainer/secrets/infra-automation-token`. Every `devenv` activation then restores `/run/secrets/infra-automation-token` from that persistent copy with `rnetadmin` read access. This makes the first automatic update cycle ready after `rebuildHost devenv` and keeps the runtime token available after later clean-checkout rebuilds.

If `modules/secrets/infra-renovate-webhook-secret` exists, `devenv` activation seeds `/var/lib/infratainer/secrets/infra-renovate-webhook-secret` from it before restoring the runtime webhook secret file with `rnetadmin` read access. This is optional; generated local secrets are preferred unless a specific shared secret must be retained.

If activation cannot see the live secret tree, provision the live secret modules manually before automatic validation or deploy builds from `/var/lib/infratainer/checkout`:

```bash
sudo install -d -o rnetadmin -g rnetadmin -m 0750 /var/lib/infratainer/secrets
sudo install -o rnetadmin -g rnetadmin -m 0640 modules/secrets/*.nix /var/lib/infratainer/secrets/
sudo install -d -o root -g rnetadmin -m 0750 /run/secrets
sudo install -o root -g rnetadmin -m 0640 modules/secrets/infra-automation-token /run/secrets/infra-automation-token
sudo install -o root -g rnetadmin -m 0640 /path/to/github-com-token /run/secrets/github-com-token
```

The directory must include any helper files imported by host secret modules, such as `infraAutomation.nix`.

`infra-renovate-dashboard-webhook-ensure.service` maintains this Forgejo repository webhook for Dependency Dashboard checkboxes:

```text
URL: http://10.255.0.1:1044/renovate-dashboard
Content type: application/json
Secret: generated/restored from /run/secrets/infra-renovate-webhook-secret
Trigger: issue events
```

After changing this automation module, apply it with `rebuildHost devenv`; the switch starts the listener and the ensure service creates or updates the Forgejo webhook. The ensure service mutates only this repository's webhook configuration.

The URL is intentionally mesh-local. Do not expose this listener through the public reverse proxy. The daily `infra-renovate.timer` remains the fallback if the webhook is disabled or temporarily unreachable.

## Renovate Labels

`renovate.json` labels eligible PRs with `infra-auto-merge`. The promoter only merges PRs with that label after validation passes.

Major container updates are labeled `manual-update`. They stay open until a human approves the PR in Forgejo. After approval, `infra-promote` validates the PR against the same flake and host build checks, then merges it through the Forgejo API if validation passes.

Manual approvals are evaluated against the current PR head when Forgejo exposes the review commit SHA, so a Renovate rebase or update requires a fresh approval.

Container updates are split by service or risk rather than one broad container PR. Paired images that should move together, such as Technitium DNS replicas, Authentik server/worker, Hudu web/worker, and Immich server/machine-learning, remain grouped. Hudu is pinned to published version tags instead of `latest` so Renovate can monitor and update it. Stateful datastore images are labeled `stateful-data` and `manual-update`. The UniFi MongoDB image is constrained below MongoDB 8 until the UniFi container compatibility policy is changed.

Lock-file maintenance uses Renovate's default schedule from `config:recommended` and is only created before 04:00 on Monday. When the dashboard lists lock-file maintenance as rate-limited outside that window, that is expected; it should become schedulable during the next Monday maintenance window.

The stable NixOS channel input is handled by a scoped regex manager plus a self-hosted post-upgrade task because Renovate 41.169.3 detects `nixos-26.05` with the native `nix` manager but cannot replace the `flake.nix` ref before refreshing `flake.lock`. `infra-renovate` therefore allows only this post-upgrade command:

```bash
nix flake update nixpkgsStable
```

## Container Image Updates

The Docker image pull timer remains enabled through `services.containerAutoUpdate`. The containers profile enables the shared `infra-update-report@.service` so Docker auto-update failures can create or update Forgejo issues from the affected host.

High-risk containers are skipped from digest-drift restarts on each host and are instead handled by Renovate PRs. Low-risk containers continue to pull and restart automatically when the image ID changes. The updater logs structured `container_update_event` lines with container name, image, service, old image ID, new image ID, and action.

Run the Infratainer update flow manually through the systemd units on `devenv`, not by invoking the generated binaries from a normal shell user. The units run as `rnetadmin` and use the managed checkout, logs, and secrets under `/var/lib/infratainer` and `/var/log/infratainer`.

```bash
sudo systemctl start infra-renovate.service
sudo systemctl start infra-promote.service
sudo systemctl start infra-deploy.service
sudo systemctl status infra-renovate-dashboard-webhook.service
sudo systemctl status infra-renovate-dashboard-webhook-ensure.service
```

Use only the first command when you just want Renovate to create or refresh PRs. Run `infra-promote.service` after reviewing or approving manual PRs. Run `infra-deploy.service` after promoted PRs have merged and should be deployed to the fleet.

Check the timers:

```bash
systemctl list-timers infra-renovate.timer infra-promote.timer infra-deploy.timer docker-container-auto-update.timer nixos-upgrade.timer
```

Inspect failures:

```bash
journalctl -u infra-renovate.service
journalctl -u infra-renovate-dashboard-webhook.service
journalctl -u infra-renovate-dashboard-webhook-ensure.service
journalctl -u infra-promote.service
journalctl -u infra-deploy.service
journalctl -u docker-container-auto-update.service
```

Validate Renovate changes with the deployed Renovate package on `devenv`:

```bash
renovate-config-validator renovate.json
sudo -n -u rnetadmin bash -lc 'RENOVATE_DRY_RUN=full LOG_LEVEL=debug infra-renovate'
```
