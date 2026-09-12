# Production audit — 2026-09-12

The source and live review found five material security risks and three smaller
reliability/configuration defects. Safe, compatibility-preserving source fixes
were applied, reviewed, committed, and rolled out host by host. Runtime secrets
were migrated without printing their values; no datastore schema, firewall
appliance, release, or `ai1` host was mutated.

## Scope and current health

- Reviewed the current 125 tracked files, with complete security review of the
  runtime Nix, shell, Python, host, network, secrets, image, deployment, and test
  surfaces. Historical investigation documents were supporting evidence rather
  than executable scope.
- Performed read-only checks on `devenv`, `rp1`, `apps1`, `apps2`, `apps3`, and
  `db1`. `ai1` remains unreachable at `10.1.13.10`, consistent with its
  deployment-only/offline topology state.
- All six running hosts had zero failed systemd units, active fallback and
  container-update timers, healthy recent automation results, current WireGuard
  handshakes, and the pre-DNAT `mesh-ingress` guard installed.
- Root filesystems were 15–41% used and data filesystems were 1–50% used. All
  declared production containers were running; health checks reported healthy
  where images define them.
- The eight sampled HTTPS applications returned expected 200/302 responses with
  valid TLS. The two short-lived Technitium certificates expire September 16 and
  had renewed successfully on September 9; mail TLS expires November 12.
- PostgreSQL readiness passed. Valkey now rejects unauthenticated `PING`; Hudu,
  Immich, Paperless, Pelican, and RedisInsight credentials authenticate as
  separate named ACL users.

## Findings and disposition

| Severity | Finding | Disposition |
| --- | --- | --- |
| High | Renovate could automatically validate executable Nix input updates while the production secret directory and Git credential were available to impure evaluation. A compromised upstream input could read or disclose fleet credentials before merge. | Fixed. All Nix input/lock updates now require current human approval. Candidate builds copy synthetic templates into the disposable checkout, unset secret/Git credential variables, and run restricted pure evaluation. Isolated `flake show` and synthetic-secret builds exercise this path. |
| High, conditional | The instance Forgejo runner was privileged, mounts the production host Docker socket, and received a Forgejo admin token. Any admitted job is effectively root on `apps2` and can pivot over the trusted mesh. | Admin-token injection and Docker `--privileged` are removed. The socket remains host-root-equivalent, so only trusted jobs are acceptable until the runner moves to a dedicated disposable host without production mesh/data access. |
| Critical | Live ignored files under `modules/secrets/` were copied world-readable into the Nix store by `path:` evaluation; secret-bearing Nix keys and the OPNsense helper also materialized credentials. | Duplicate in-tree files were removed after byte comparison with the protected external overlay. Containers and OPNsense use protected runtime files, and garbage collection removed all detected secret-bearing store snapshots. Credentials present in those historical snapshots still require coordinated rotation. |
| Medium | Every mesh peer could issue unauthenticated Valkey commands; live `ACL DRYRUN` confirmed that `default` could execute `FLUSHALL`. Logical databases do not isolate applications. | Fixed. Clients were migrated and health-checked individually under named users; `default` is disabled and unauthenticated `PING` is rejected. Command/key-prefix minimization remains a defense-in-depth follow-up. |
| Medium | VMA builds generated a derivation-backed administrator password and published its plaintext in `CREDENTIALS.txt`. | Fixed. VMA packages use synthetic templates, lock password login, and retain SSH-key bootstrap; no credential file is produced. |
| Medium | `ai1` would expose an unauthenticated, single-slot, hour-long llama.cpp API to all RFC1918 source ranges. One reachable client could monopolize GPU/CPU/RAM. | Source access is narrowed to the operator desktop `10.1.13.10/32`. `ai1` remains offline because its configured address collides with that desktop; assign `ai1` a different reserved address before installation or activation. |
| Low | Runner re-registration used a long-lived Forgejo administrator token inside the job runner. | Fixed locally. The runner no longer receives or calls Forgejo with an admin token; label changes fail closed for manual deregistration. |
| Low | The `nixos-vscode-server` flake override targets an upstream input that no longer exists, producing warnings without affecting the selected dependency. | Fixed locally by removing the ineffective override. |
| Low | Generated Proxmox VM config set the RTC to local time while NixOS expects UTC, allowing clock jumps after boot. | Fixed locally by emitting `localtime: 0`. |

## Other verified controls

- Public traffic cannot directly reach Docker services bound to mesh addresses;
  the pre-DNAT nftables guard is present on every running mesh host.
- Promotion binds expected bot/repository/base/branch, fetched SHA, current human
  approval for manual changes, validation, and merge `head_commit_id`.
- The webhook is mesh-bound, HMAC authenticated, body/time bounded, and can only
  enqueue the fixed Renovate unit.
- Migration SSH remains ForceCommand-restricted; Docker commands use a bounded
  grammar and SCP/SFTP is filesystem-confined. Offline escape/recovery checks pass.
- OPNsense API TLS verification defaults on and mutation requires a usable
  savepoint; failure paths retain rollback.

## Validation and rollout boundary

- Offline credential, runner, promotion, webhook, container-update, firewall,
  and migration regression checks passed, along with JSON validation, shell
  syntax checks, formatting, and whitespace checks.
- Restricted `nix flake show` succeeded in an isolated checkout containing only
  synthetic secret modules. All seven exported synthetic-secret NixOS toplevel
  builds passed against the final source tree.
- No VMA image was generated; all VMA derivations are now secret-free and no
  plaintext credential artifact is defined.
- `db1`, `apps1`, `apps3`, `apps2`, and `devenv` were deployed in that order with
  health gates. Both desktop-to-`devenv` SSH sessions remained established.
- The full Forgejo runner isolation and historical credential rotation remain
  coordinated follow-ups. `ai1` must not be activated until its IP collision is
  resolved.
