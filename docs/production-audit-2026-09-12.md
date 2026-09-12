# Production audit — 2026-09-12

The source and live review found five material security risks and three smaller
reliability/configuration defects. Safe, compatibility-preserving source fixes
were applied locally. No host was activated, no container was restarted, no
credential was read or changed, and no firewall, datastore, lockfile, release,
or remote checkout was mutated.

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
- PostgreSQL readiness passed. Valkey returned `PONG`, and `ACL DRYRUN default
  FLUSHALL` returned `OK`, confirming that its default user remains
  unauthenticated and unrestricted.

## Findings and disposition

| Severity | Finding | Disposition |
| --- | --- | --- |
| High | Renovate could automatically validate executable Nix input updates while the production secret directory and Git credential were available to impure evaluation. A compromised upstream input could read or disclose fleet credentials before merge. | Fixed locally. All Nix input/lock updates now require current human approval. Candidate builds copy synthetic templates into the disposable checkout, unset secret/Git credential variables, and run restricted pure evaluation. Isolated `flake show` and synthetic-secret builds exercise this path. |
| High, conditional | The instance Forgejo runner was privileged, mounts the production host Docker socket, and received a Forgejo admin token. Any admitted job is effectively root on `apps2` and can pivot over the trusted mesh. | Admin-token injection and Docker `--privileged` are removed. The socket remains host-root-equivalent, so only trusted jobs are acceptable until the runner moves to a dedicated disposable host without production mesh/data access. |
| Critical | Live ignored files under `modules/secrets/` were copied world-readable into the Nix store by `path:` evaluation; secret-bearing Nix keys and the OPNsense helper also materialized credentials. | Duplicate in-tree files are removed after byte comparison with the protected external overlay. Containers and OPNsense use protected runtime files. All credentials present in prior store snapshots still require coordinated rotation. |
| Medium | Every mesh peer can issue unauthenticated Valkey commands; live `ACL DRYRUN` confirmed that `default` may execute `FLUSHALL`. Logical databases do not isolate applications. | Compatibility ACL users and authenticated client configuration are staged. Disable `default` only after every live client is observed under its named user and unauthenticated access can be rejected without outage. |
| Medium | VMA builds generated a derivation-backed administrator password and published its plaintext in `CREDENTIALS.txt`. | Fixed locally. VMA packages use synthetic templates, lock password login, and retain SSH-key bootstrap; no credential file is produced. |
| Medium | `ai1` exposes an unauthenticated, single-slot, hour-long llama.cpp API to all RFC1918 source ranges. One reachable client can monopolize GPU/CPU/RAM. | `ai1` is offline, so no live exposure exists today. Before installation, choose authorized client addresses and either narrow the firewall to them or place llama.cpp behind authenticated mTLS/API-key ingress; also reduce request limits where compatible. |
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
- No VMA image was generated because that would create another plaintext
  credential artifact. The changed QEMU config is evaluated directly instead.
- These source changes are not deployed. Review and commit them, then use the
  normal managed rollout. The secret, Valkey, runner-isolation, VMA-bootstrap,
  and `ai1` access-control migrations require explicit staging and acceptance
  checks; they should not be bundled into an unattended activation.
