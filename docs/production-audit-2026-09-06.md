# Production audit — 2026-09-06

The review found seven security issues, plus defects in container update detection
and failure-report deduplication. Following user approval, the compatible
corrections were deployed to all six running hosts on September 6, 2026. Live
verification passed. Credential migration, Valkey authentication and a restore
test remain separate production work, detailed below.

## Scope and evidence

- Reviewed all 119 tracked files at `2c5a743fb80e2406e901585998658c6cece77796`,
  including host definitions, shared profiles, deployment and migration tools,
  templates, tests and documentation. Independent source review supplemented
  architecture and trust-boundary analysis.
- Performed read-only runtime checks on `devenv`, `rp1`, `apps1`, `apps2`, `apps3`
  and `db1`, using existing SSH identities. `ai1` refused SSH on `10.1.13.10`;
  the user confirmed it is deliberately offline / awaiting installation.
- Examined effective nftables rules and container/service status. Used Valkey
  `PING` and `ACL DRYRUN`; no application data commands, writes or flushes ran.
- Production's managed checkout was
  `aa21b2ea49f65849c2f219b1dc74866adc7c83fe`, different from the audited checkout.
  Before rollout, reviewed that difference and confirmed the deployed Nix and
  shell sources matched the successfully built validation snapshot.
- The initial audit was read-only except for stopping the unused development
  container below. The subsequent authorized rollout changed host configurations
  as recorded below. No dependency update, image migration, reboot, backup restore
  or tagged release was performed.
- After the user confirmed their development container was not currently needed,
  stopped `bleuagent-local` to end its restart loop. Inspection confirmed `exited`
  and `restarting=false`; its image, data, configuration and `unless-stopped`
  policy remain intact. It can be resumed with `docker start bleuagent-local`.

This is a repository and reachable-host audit, not a certification of external
OPNsense/Proxmox policy, every dependency advisory, OIDC login behavior, mail
delivery or recovery. Live secret values were not included in the report.

## Findings and corrections

| Severity | Finding and evidence | Correction / remaining work |
| --- | --- | --- |
| Medium | Mesh-bound Docker publications accept packets arriving on physical interfaces. On `db1`, DNAT matches `10.255.0.11:1025` without requiring `wg-mesh`; Docker forwarding accepts the result and `DOCKER-USER` is empty. A same-VLAN source passes reverse-path checks. | Added `mesh-ingress` before DNAT in the shared mesh profile, now active on all six running hosts. Preserves WireGuard, local Docker bridges and deliberate physical-address publications. Isolated packet tests reproduce and block the bypass. |
| Medium | Valkey's default user accepts unauthenticated access. `PING` returned `PONG`; `ACL DRYRUN default` permitted `GET`, `SET` and `FLUSHALL`. Shared logical databases do not isolate applications. | Network correction reduces exposure. Per-application authentication and data/command isolation remain a coordinated migration; disabling the default user immediately would break current clients. |
| Medium | Inline application credentials, runner command interpolation, generated VMA credentials and in-tree live secrets can enter readable Nix artifacts. Gitignore does not protect a `path:` flake snapshot. | Added compatible runtime env-file support for the application containers and runner, and corrected unsafe examples. Existing values and old store generations still require staged migration/rotation. UniFi's credential mapping and VMA bootstrap credentials remain separate work. |
| Medium | Forgejo API bearer headers are passed in curl command arguments in automation, reporting and runner deregistration. Local process observers can read arguments without reading protected token files. | All four callers now provide headers through a pipe/file descriptor. Tests verify both the resulting header and absence of the token in arguments. Runner registration still uses its CLI token argument; that is explicitly documented as residual exposure. |
| Medium | OPNsense recommendations expand a single observed source into a `/24` in both preview and apply payloads. | Both paths retain exact source addresses. Neighboring hosts remain distinct. Existing transaction, TLS and rollback controls are preserved. Existing router rules were not inspected or rewritten. |
| Medium | Unattended deployment enrolls missing SSH identities using unauthenticated `ssh-keyscan`. | Deployment now requires an existing verified key and fails before rebuilding when one is missing. Existing keys remain intact. Five reachable remote hosts have entries; `ai1` does not. Presence alone does not independently reverify how those keys were originally enrolled. |
| Low | The extra mail HTTPS relay sends loopback as the client address in its PROXY header. This degrades client attribution and controls that depend on it. | The shared front listener now sends the original address directly to Stalwart. The DNS branch removes the header on a loopback-only relay, preserving raw TLS and its existing source ACL. |

Docker documents that published traffic is translated and forwarded before host
INPUT filtering, so binding a publication to an address does not establish an
ingress-interface boundary. See [Docker firewall behavior](https://docs.docker.com/engine/network/packet-filtering-firewalls/)
and [port publishing](https://docs.docker.com/engine/network/port-publishing/).
The relay correction uses NGINX's [stream PROXY protocol](https://nginx.org/en/docs/stream/ngx_stream_proxy_module.html#proxy_protocol)
and [stream real-IP support](https://nginx.org/en/docs/stream/ngx_stream_realip_module.html).

Two reliability corrections accompany these findings:

- The container updater compares each running container's image with the pulled
  image, instead of comparing the cached tag before and after the pull. This
  catches previously pulled updates, failed prior restarts and shared-tag drift.
  Stopped units remain stopped; missing units and inspection failures fail the job.
- Failure issue titles include the hostname, preventing one host's report from
  overwriting another host's report for the same source/status.

SCP/SFTP also received the user-approved directory confinement: a Bubblewrap
filesystem view exposes `/home/docker` and accessible migration staging, together
with the minimal read-only OpenSSH runtime and public account/group databases.
It excludes host `/proc`, runtime sockets, migration keys and unrelated store
paths. The normal streamed migration protocol is unchanged. The investigated
SFTP process-memory write failed with permission denied; that speculative escape
is not reported as a validated vulnerability.

## Operational observations

| Check | Result |
| --- | --- |
| Failed systemd units | None on the six reachable hosts. |
| Root filesystems | Approximately 24–35% used; no immediate root-disk pressure. |
| Data filesystems | Approximately 0–50% used across the reachable hosts. |
| Declarative containers | Running; configured health checks passed. |
| WireGuard | Active peers had recent handshakes. `gs1` had none and is not exported. |
| DNS | Both DNS hosts resolved `example.com`. |
| HTTPS samples | Git, Access, Search, Photos, Docs and Cloud returned expected 200/302 responses with certificate verification. This does not exercise application login or write workflows. |
| Monitoring | Prometheus reported both its OpenTelemetry and Stalwart targets up, without scrape errors. |
| DNS certificates | Renewed September 6; expire September 12 at approximately 16:28 UTC. These use the configured short-lived ACME profile. |
| Development container | `bleuagent-local` had over 15,000 restarts with exit code 1. The user confirmed it belongs to ongoing development and is not currently needed. Stopped it and verified the restart loop ended, retaining its image/data/configuration. Its application defect remains development work before reuse. |
| `ai1` | User confirmed it is deliberately offline / awaiting installation. Added `fleetDeployment = false` to exclude it from bulk deployment and its SSH identity checks. Explicit rebuilds and all build validation remain available. Enable fleet deployment only after installation and verified SSH enrollment. |
| Backups | User confirms Proxmox Backup Server manages backups; the backup filesystem was checked and restores have succeeded historically. This exact setup has not been restored in a test. Coverage of each data disk and physical `ai1` remains unverified. |

## Validation

All seven exported NixOS toplevels built successfully: `devenv`, `rp1`, `apps1`,
`apps2`, `apps3`, `db1` and `ai1`. Builds used a tracked-file snapshot without
in-tree secrets, the existing external secret overlay, `--impure`,
`--no-write-lock-file`, `--no-link`, two build jobs and four cores. No VMA or ISO
was generated, and the lockfile is unchanged.

Passed regression checks:

- Actual evaluated NGINX routes: 160 source/SNI cases, original mail client
  IP/port, unchanged TLS at DNS backends, rejection of untrusted PROXY input.
- Actual evaluated mesh rules in disposable network namespaces: the original
  physical-ingress DNAT bypass, denial after the fix, WireGuard-named and Docker
  bridge paths, and the deliberate physical DNS publication. The test simulates
  interface ingress; it does not replace live WireGuard/OPNsense integration tests.
- Built migration helper with real OpenSSH: SCP and SFTP file transfers, read and
  write operations, traversal and symlink escapes, and access to host secrets and
  sockets. Only temporary fixture data was written.
- Offline migration command/recovery suite; deployment promotion and identity
  guards; webhook validation; OPNsense transaction/rollback and exact-source cases;
  container update scenarios; all four API-header callers.
- Built deployment tools retain `ai1` for explicit rebuilds and release validation
  while excluding it from bulk deployment and required SSH identities.
- Relevant Bash syntax, Renovate JSON syntax and changed Nix formatting/syntax.
  Existing formatting was preserved in files that already differed from nixfmt.

The scan runtime did not expose a measured token-usage total.

## Production rollout

Activated the validated configurations one host at a time, starting with `devenv`
to verify the physical Remote SSH path. Each activation ran under systemd with a
15-minute automatic rollback armed first. After successful host and service
checks, cancelled that host's timer before proceeding. No rollback was needed.

| Host, in rollout order | Accepted, September 6 (CDT / UTC) | Runtime result |
| --- | --- | --- |
| `devenv` | 16:57:24 / 21:57:24 | Both existing VS Code SSH sessions survived; a fresh physical SSH connection succeeded. Development containers unchanged. |
| `db1` | 16:58:46 / 21:58:46 | PostgreSQL, Valkey, OpenTelemetry and Prometheus container identities unchanged; database readiness and monitoring passed. |
| `apps2` | 17:01:29 / 22:01:29 | Forgejo runner recreated as expected, using the identical image digest; its daemon is running with zero restarts. Other containers unchanged. |
| `apps3` | 17:01:58 / 22:01:58 | All seven container identities unchanged; configured health checks and sampled applications passed. |
| `apps1` | 17:02:27 / 22:02:27 | All nine container identities unchanged; DNS, Git, Access and mail HTTPS passed. |
| `rp1` | 17:03:20 / 22:03:20 | NGINX restarted with the new configuration; mail and DNS TLS routes passed. |

All six current-system and boot-profile paths match their approved build outputs.
There are no failed systemd units, and the new mesh ingress table is present on
every host. SSH listeners restarted during activation; the existing `devenv`
sessions retained the same connections and processes. No network interface or
WireGuard restart was required. `ai1` was not contacted or activated during rollout.

Live checks after activation included:

- PostgreSQL readiness, Valkey `PING` over the mesh and both Prometheus scrape
  targets healthy, without application data changes.
- DNS resolution through both application hosts' physical addresses.
- Verified HTTPS responses for Git, Access, Search, Photos, Docs and Cloud.
- Verified mail HTTPS and both DNS administration sites through `rp1`, plus
  certificate-verified SMTP and IMAP TLS handshakes and protocol greetings. Mail
  delivery, application login and write workflows were not exercised.
- The deployed forced-command SFTP path: `/home/docker` accessible and
  `/proc/self/maps` unavailable. The earlier isolated regression suite covers
  permitted file writes and escape attempts.
- Unchanged container sets and image tags across the fleet. Only the runner's
  container identity changed; its actual image digest was checked before and
  after recreation. `bleuagent-local` remains stopped with its data retained.

Previous closures are protected from garbage collection on each host under
`/var/lib/infra-audit-rollout/20260906T215555Z/previous-system`. The same root-only
directory contains old/new system paths, the container baseline, acceptance time
and `rollback.sh`. If rollback is needed, run the following on the affected host
to restore both its system profile and active configuration independently of SSH:

```bash
sudo systemd-run --unit=infra-audit-manual-rollback-20260906 --collect \
  /var/lib/infra-audit-rollout/20260906T215555Z/rollback.sh
```

The approved configuration accompanies this report on `indev`, the source used by
scheduled deployments and fallback upgrades. The managed checkout refreshes from
that branch during its next normal workflow. Scheduled update timers remain
enabled; no extra update or release job was triggered during rollout.

## Remaining production work

1. Provision persistent runtime env files using existing values first. Remove
   duplicated sensitive `keys` entries, build, activate and verify one service at
   a time. Move UniFi credentials with its MongoDB mapping in a separate change.
   Rotate exposed credentials with their consumers after migration. Preserve
   application encryption keys, historical decryption needs and recovery copies;
   do not blindly rotate Hudu/Paperless/OCIS or database encryption material.
   Old Nix artifacts remain an exposure until rotation/revocation is complete.
2. Inventory Valkey clients: Hudu, Immich, Paperless, Pelican, Authentik and Redis
   Insight, plus any undeclared consumers. Introduce distinct authenticated users
   while retaining compatibility for existing clients, then migrate and test
   clients individually. Restrict commands and key/channel prefixes where the
   application supports them; use separate instances when shared keyspaces or
   broad commands prevent sound isolation. Disable unauthenticated default access
   only after all clients have moved. Verify session, queue and background-job
   behavior, and that unauthenticated commands fail. Keep rollback credentials
   until those checks pass.
3. Restore recent PBS backups into isolated guests with network interfaces
   disconnected before first boot. Include every persistent data disk and required
   secret/key material. Prevent restored timers, mesh identities, mail and webhook
   integrations from contacting production. Verify PostgreSQL 18 recovery and
   representative application data, file access and decryption. Record backup
   age, restore duration and application checks; separately verify physical `ai1`
   coverage. Filesystem checking alone does not demonstrate application recovery.

Existing deployment host fingerprints still need independent verification through
an authenticated administrative channel; this audit checked their presence and
used strict matching without enrolling new keys.

Authentication changes, credential rotation and the recovery test remain
outstanding. Configuration activation is complete. The existing stateful-image
manual-review policy remains intact.
