# Production audit — September 4–5, 2026

The source and live audit found security weaknesses and several failing services.
Following authorization, repairs were activated on all six reachable production
hosts: `devenv`, `rp1`, `apps1`, `apps2`, `apps3`, and `db1`. Application health,
credential rotation, certificates, and migration compatibility were checked live.
The implementation was published as `8d6df0ff1e7439fa21b6c856ca362e0a2773e884`
on `indev`; the managed deployment checkout was fast-forwarded to it. Every host
then built that published source using its own persistent secret overlay, and
all saved update/maintenance timer states were restored.

The rollout used an isolated checkout based on production `origin/indev`
`527e5ef41986da4f5c6f58c5c1e527877de661b2`. The original working tree contains
older dependency pins plus existing user changes; its pending `ai1` and lockfile
work was preserved. **Reconcile that working tree with published `indev` before
using it for another deployment.** No dependency lock update, datastore image
upgrade, reboot, disk resizing, or `ai1` deployment was performed by this rollout.

## Findings and disposition

| Priority | Finding | Repair and evidence |
|---|---|---|
| High | A published apps3 WireGuard private key matched its running identity. A documented Hudu database password was also still active. | Redacted the notes; rotated apps3's identity across all active peers and the Hudu database role plus both clients. The new database password authenticates; the old password is rejected. New WireGuard identities use persistent root-only runtime files. Historical copies remain exposed but those credentials are retired. |
| Medium | Restricted migration SSH used a prefix check followed by `eval` and unrestricted Docker operations. | Replaced shell evaluation with a strict argument parser and a bounded migration command vocabulary, fixed executable/config paths, and a root-owned identity directory. Live legitimate migration succeeded; shell injection and privileged-container commands were rejected. SCP/SFTP remain supported. |
| Medium | Promotion could mask validation failures, race over a shared checkout, or merge a different commit from the one reviewed. | Explicitly check every prerequisite, serialize workflows with `flock`, validate the exact PR SHA, require the expected bot/repository/base, read all review pages, and require current writer approval for manual updates. The merge request is guarded by the validated SHA. Focused failure and compatibility tests pass. |
| Medium | The OPNsense helper disabled TLS verification by default and could lose rollback protection. | Verify TLS by default; validate responses; require a usable savepoint before writing; retain rollback until application is confirmed. All 22 offline success/failure cases pass. No live router rules were changed. |
| Low | Public TLS stream routing bypassed the HTTP-only DNS administration restriction. | Enforce private-source checks before choosing DNS administration upstreams. The pinned NGINX binary passed 158 source/SNI cases, including public mail. Internal DNS administration and public-facing application HTTPS work. External source preservation still requires a check from outside the VPN. |
| Low | The mesh webhook spawned unbounded request handlers and waited for Renovate to finish. | Bound handling with an absolute request deadline and queue the systemd job asynchronously while retaining HMAC checks. Slow-client, signature, and dispatch tests pass. |
| Medium; partly remediated | Inline Nix secrets and secret files in a `path:` flake can enter readable Nix artifacts. | Moved active mesh keys, migration keys, ACME credentials, reporter tokens, and Hudu environment values to protected persistent runtime files. Other applications still use inline values; staged conversion and appropriate rotations remain necessary. Gitignore alone does not exclude secrets from a path flake. |
| Urgent reliability | Jaeger could not write its Badger volume as UID 10001. | Corrected only the volume root ownership and retained UID 10001. Jaeger serves HTTP 200 without a restart loop. |
| Urgent reliability | The telemetry collector rejected the removed `logging` exporter; both Prometheus targets were down. | Use `debug` and Stalwart's `/metrics/prometheus` endpoint. The collector is running and both Prometheus targets report healthy with no scrape error. |
| Urgent reliability and persistence | Pelican crash-looped behind HTTPS and wrote configuration to an anonymous volume. | Preserved and verified its existing state, corrected proxy settings and named-volume mount paths, and restored the expected log directory ownership. Pelican is healthy, redirects normally, and preserves its application configuration across a controlled restart. |
| Urgent reliability | DNS administration served certificates expired in May despite current PEM certificates on disk. Renewal hooks also referenced nonexistent container units. | Export current installed PEM/key files into an atomic PKCS#12 replacement and reload the actual Docker units. Repaired both existing PFX files separately. Both served certificates pass trust, hostname, expiry, and fingerprint checks, and both DNS resolvers answer queries. |
| Reliability and data safety | Migration could stop auto-removed declarative containers incorrectly and mishandle pipeline or recovery failures. | Use systemd lifecycle operations and dependency snapshots, validate archives before downtime, propagate pipeline failures, recover previously running source consumers, and leave partially written destinations stopped. Regression checks and a disposable live transfer passed. |
| Reliability | Backend consumers could start before their Docker network existed. | Add creation and lifecycle ordering to the applicable declared consumers. All six configurations build and the deployed containers run. |
| Reliability | Rebuild scripts restarted DBus after unrelated deployment failures. | Attempt recovery only when systemd is actually missing from the system bus. Other failures are preserved and reported. |
| Maintenance | Pinned Nixpkgs marks Angie insecure due to delayed security maintenance. | Use the pinned maintained NGINX 1.30.4 with stream support. Ingress, mail HTTPS, DNS administration, and routing checks passed. |
| Urgent operations | Remote fallback updates failed because their external secret modules and reporter token were absent. | Provision each remote's own module and required imports, persistent runtime dependencies, and reporter token. Devenv retains the fleet overlay. Final fallback evaluation results are recorded below. |

## Production safeguards and rollout observations

The active management path enters through the upstream VPN gateway and the VLAN
interface, independently of the fleet `wg-mesh` keys. Primary-interface addresses
and routes were unchanged. SSH and mesh connectivity were checked during staged
activation; no upstream VPN or OPNsense configuration was changed.

Scheduled updates, promotion, deployment, Docker refresh/prune, and Nix garbage
collection were held during the rollout. Runtime masks alone did not override
NixOS's unit links, so an explicit systemd maintenance condition was added and
verified to skip execution. Original timer states were saved per host and restored at approximately 20:35
CDT on September 5. All temporary maintenance conditions and masks were removed.
The next devenv runs were Renovate at 01:05, promotion at 01:45, deployment at
02:35, and fallback upgrade at 05:08 CDT on September 6. The shared workflow lock
serializes Renovate, promotion, and deployment. No pending manual PR was approved
or merged; runner PR #88 remains unchanged on runner v13 while production stays
on v12.

The initial credential provisioning had an error: a text replacement associated
ACME with a WireGuard key file. This caused ACME failures and systemd logged rp1's
old key as an invalid environment assignment. The mappings were corrected,
explicit runtime-file validation was added, and rp1's identity was also rotated
across the fleet. No current rp1/apps1/apps2 WireGuard key was found in the
subsequent journal check. Retained logs and old generations may contain retired
credentials; do not revert to those identities.

Pelican's initial restored log directory had incorrect ownership. It was
corrected to the image's UID/GID 82 and mode 770 on the two affected directories.
Its existing application key was preserved. This was a restore metadata issue;
no application encryption keys were changed.

The existing generation was retained through a dedicated GC root on every host.
Before the final closure copies, remote root filesystems had 10.22–12.39 GiB free;
the final deltas needed less than 0.02 GiB per host. The intentionally small OS
disks were retained. Existing generation and journal limits remain enabled.

## Validation

- Six production toplevels built successfully with `INFRA_SECRETS_DIR` and
  `--impure --no-write-lock-file`. Earlier audit builds also covered the pending
  local `ai1` configuration; it was not included in production deployment.
- `tests/test-infra-automation.py`, `tests/test-infra-webhook.py`,
  `tests/test_firewall_rules.py`, and
  `modules/profiles/containers/tests/check_migration.py` passed.
- `docs/checks/rp1-dns-admin.py` passed all 158 routing cases against the actual
  pinned NGINX binary. The old public DNS administration behavior fails that
  regression check.
- Applicable Bash syntax checks, Renovate JSON validation, generated NixOS
  script builds, and formatting checks passed.
- A live transfer from apps1 to apps3 used two newly created, labeled disposable
  volumes. File SHA256, mode/ownership, and symlink target matched; both test
  volumes were removed afterward. No production volume was used in this test.
- Hudu's new database credential works and its former credential is rejected;
  the web and worker containers run without restart loops. The Hudu application
  endpoint returns HTTP 200 over validated HTTPS.
- Pelican's application configuration survived a controlled restart. Its HTTP
  and HTTPS endpoints redirect normally and the container is healthy.
- Jaeger returns HTTP 200; the collector runs; both Prometheus targets are up.
  Forgejo, mail, Immich, and Search return HTTPS 200; Paperless redirects normally.
- Both DNS admin certificates match their current PEM files and expire September
  12, 2026, consistent with the configured short-lived certificate profile.
  Both VLAN resolvers answer recursive queries. A failed PFX export preserves
  the existing file and removes its temporary output.
- Every host successfully built the published Git revision with its persistent
  secret overlay and the tools from its actual `nixos-upgrade` service. An initial
  manual rp1 probe lacked Git on its interactive PATH; rerunning with the service
  PATH passed. These were builds, not another system activation.
- All original timers are enabled and active with future scheduled runs. Audit
  masks/conditions are gone. The bot can read the repository, the webhook's
  persistent/runtime secret copies match, and the service user can read its
  credentials. Manual issue creation was not used as a reporter test.

The finalized source security scan records eight findings (one high, five medium,
two low) from 112 reviewed files. Live operational findings are additional.
Scanner token usage was not provided by the tool. Private diagnostic artifacts
are under `/tmp/infra-rollout-20260905`, mode 0700; they contain recovery material
and must not be committed or shared as ordinary logs.

## Recovery material

- Every host: `/var/lib/infra-audit-rollout/system.before` and `timers.before`,
  plus `/nix/var/nix/gcroots/infra-audit-rollout/before` and `candidate`.
- db1: `/mnt/data/infra-audit-rollout/hudu/before.dump`; its archive listing was
  validated. This is not a full restore test.
- apps3: `/mnt/data/infra-audit-rollout/pelican/` contains preserved configuration,
  volume archives, checksums, and inspection metadata. Keep these confidential.
- apps1/apps2: `/var/lib/infra-audit-rollout/dns-certificates/` holds the old PFX
  for diagnosis; those certificates are expired and contain private key material.

For an installation still using Pelican's old mount paths, preserve its current
anonymous `/pelican-data` and logs before stopping the auto-removed container.
Verify the archives, retain its `.env` and application key, and restore into
empty corrected named volumes with the image's ownership and modes. Reconcile
any nonempty destination rather than overwriting it. Verify persistence across
a controlled restart. Never infer that the application has no state just because
the old named volumes are empty.

A generation rollback does not undo database-password changes or volume moves.
Any recovery configuration must retain the current WireGuard identities and
runtime credential paths. Do not blindly activate the old generation.

## Remaining work and limits

- Migrate the remaining inline application credentials to runtime files one
  service at a time, then rotate exposed values using service-specific procedures.
  Encryption/signing keys can require data migration and must not be reset
  casually. Historical stores, images, caches, clones, and backups retain old
  values; deleting every generation is not a substitute for rotation.
- Remote reporters currently reuse the existing automation credential. Provision
  narrowly scoped issue-reporting tokens separately from the promotion/deployment
  token as part of the remaining credential work.
- The standalone `bleuagent-local` development container on devenv is outside
  this flake. It has a pre-existing restart loop (over 14,000 restarts) because
  its image rejects `BLEUAGENT_TOKEN` and requires `BLEUAGENT_TOKEN_FILE` with a
  mounted secret. It was left for a separate development-container repair.
- `gs1` was unreachable and had no recent mesh handshakes. Update its peer
  configuration and secret provisioning before bringing it online. `ai1` is
  pending separate installation work and was not deployed.
- Verify DNS administration rejection from a real external client, confirming
  that upstream NAT preserves the source address seen by rp1. Local routing tests
  cannot establish that property. SMTP/mail delivery and application OIDC flows
  were not tested end to end.
- The Forgejo runner intentionally retains privileged Docker access. Keep its
  workload limited to trusted administrators; untrusted jobs require isolation.
  Runner v13 PR #88 remains a manual update and was not approved or merged.
- Backup restore assurance remains incomplete. The audit checked selected backup
  artifacts and application state, not a full fleet restore. SearxNG also reports
  deprecated/missing optional engines in its persistent configuration while its
  search interface remains available; reconcile those settings separately.

The OPNsense helper deliberately stops before mutation if the server does not
support its rollback API. Consult the [OPNsense roadmap](https://opnsense.org/roadmap/)
and use a version-compatible rollback procedure rather than removing that guard.
