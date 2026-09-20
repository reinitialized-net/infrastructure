# Production audit follow-up — 2026-09-12

This follow-up audits baseline `e78def31661eb3523051f72d3a43493fdb00daef`.
It does not reassert the deployed-state claims in the earlier September 12 audit.
No deployment, credential rotation, lockfile update, release, push, or VMA build
was performed in this session.

## Scope and evidence limits

The Deep Security Scan coordinator completed eight independent Standard reviews
and published five findings (two medium, three low). Its aggregate says coverage
is complete, but its own report lists partial reviews, deferred runtime checks,
and exclusions; its coverage document has empty surface/deferred arrays.
Accordingly, this is a **partial static audit**, not proof of production security.

`modules/secrets` is denied by the execution environment and was excluded.
Runtime secrets, application state, edge NAT/firewall rules, effective DNS
recursion policy, Forgejo workflow admission, deployed generations, and upstream
container implementations were not inspected. Historical documents are evidence
of prior decisions and outstanding work, not independently verified current state.

The user authorized live checks against `47.190.182.76–47.190.182.80`, deriving
hostnames from this repository. The session has networking disabled. One HEAD
request to `http://47.190.182.76/` failed immediately with curl exit 7. This is
**not** evidence that the production port is closed. No successful live connection
or unauthorized data access was demonstrated.

## Findings and remediation status

| Finding | Source boundary | Action and remaining limit |
| --- | --- | --- |
| Medium: privileged `develop` account has a fixed plaintext initial password | `hosts/devenv.nix` passes `initialPassword` through `makeUser` | Replace it with `hashedPassword = "!"`; retain SSH key/groups. Effective locked status must be checked after activation without printing shadow data. |
| Medium, conditional: Forgejo jobs can control apps2's production Docker daemon | Runner manager mounts the host socket and enables job automount | Dedicated disposable CI VM is required for full isolation. Runner stop/retention decision is pending; current socket exposure remains. |
| Low: migration checksum output follows an attacker-planted symlink | Export final sidecar redirection in `migrate-volumes.sh` | Private export staging now defaults to `/mnt/data/docker-volume-backups`, outside SFTP roots; safe publication and race regressions pass offline. Native build/runtime verification remains blocked. |
| Low: first-use migration accepts an unverified destination key | `containerTools.nix` uses `accept-new` | Require strict host-key checking and administrator-owned trust. Provision verified keys before migration; old user-owned learned caches are not trusted automatically. |
| Operational: promotion validates without the intended synthetic metadata | `validate_pr` copies templates into a path no longer imported by `makeConfiguration` | Add explicit pure synthetic `checks.x86_64-linux.<host>` and build those. Preserve credential unsets and restricted evaluation; live `nixosConfigurations` remain external-overlay configurations. |

Changes are source remediation candidates until applicable final build and
runtime validation has passed. The scan's severity depends on its recorded
prerequisites; no anonymous Internet path to the runner or develop account was
established.

## Runner isolation plan

1. Reserve a dedicated CI VM ID, address, VLAN, resources and disposable storage.
   Do not co-host production data or use the shared containers profile without
   removing production migration credentials and unrelated service wiring.
2. Enforce network restrictions outside the guest: jobs controlling its Docker
   daemon can become guest root and change guest firewall rules. Do not make it
   a normal trusted WireGuard mesh peer.
3. Define permitted repositories, fork/workflow trust, labels, build privileges,
   caches and required egress. Use a scoped registration credential and preserve
   manual deregistration on label changes; never inject a Forgejo admin token.
4. Drain/deregister the old runner, register fresh state on the isolated VM,
   and preserve old data until representative workflows succeed. Remove the
   apps2 runner only through the agreed migration or immediate-disable action.
5. Verify that jobs, including guest-root jobs, cannot reach production Docker,
   production volumes, fleet credentials or management networks. Recreate the VM
   and repeat a representative workflow to prove disposable operation.

Removing only job automount or using privileged Docker-in-Docker on apps2 does
not close the production-host boundary. Actual workflow compatibility and VM
allocation are operator decisions absent from the permitted source.

## Live verification plan

Run `python3 docs/checks/production-exposure.py` to list the fixed scope without
network access. Run it with `--run` from an authorized external network and retain
its JSON lines as evidence. It uses four workers, short timeouts, TCP connections
and HEAD requests with verified TLS/SNI; it reads no response bodies, follows no
redirects and sends no credentials. It tests each configured name against all
five authorized IPs because the external NAT mappings are unavailable here.

Source policy in `hosts/rp1.nix` distinguishes these intended restrictions:

- Private-client interfaces: both DNS admin names; UniFi, pgAdmin, Redis Insight,
  Jaeger, Grafana and Prometheus names; `gs.admin.reinitialized.net`; SearXNG.
  Confirm externally that their HTTPS application interfaces deny access, with
  HTTP redirects evaluated separately. A 200 login page on a private-only service
  warrants investigation; a TLS mismatch or timeout proves neither ACL correctness
  nor application exposure.
- Public ingress: mail, documentation, media, Forgejo, photos, Matrix/Cinny,
  Paperless, Authentik, ownCloud and the three staging application names. Public
  routing does not imply that protected application data should be anonymous.
  The intended audience of `admin.staging.bleupigs.club` needs confirmation.
- DNS TCP/UDP and mail protocol listeners are intentional. Separately verify
  authoritative DNS still works and recursion is denied to external clients;
  the bundled TCP/HEAD checks do not test UDP or recursion.
- Datastore and Docker APIs should not become publicly accessible merely because
  a backend service is published on a mesh address. Review any successful public
  connection to those ports against the actual NAT and service mapping.

An internal or hairpin-NAT vantage may appear as a private client and cannot
establish WAN ACL behavior. The check script does not test every port, protocol,
application permission or authenticated endpoint.

## Outstanding operational decisions

- Choose whether to disable the apps2 runner pending isolation or temporarily
  retain it for administrator-trusted jobs.
- Supply ai1's distinct reserved IP: source assigns `10.1.13.10` to both the host
  and its intended desktop client. Do not activate the conflicting configuration.
- Confirm whether the staging admin frontend is intentionally public.
- Complete or provide evidence of historical credential rotation, preserving
  application encryption keys and service compatibility. Credential material is
  outside this session's permitted access.
- Verify effective Technitium recursion ACLs, Valkey ACLs, mail trusted-network
  settings, OIDC authorization, runtime secret-file permissions, disk/mount state,
  backups/recovery and deployed host health from an authorized runtime session.

## Validation

Passed final unchanged-area checks:

```text
python3 tests/test-api-credentials.py
python3 tests/test-container-auto-update.py
python3 tests/test-infra-automation.py
python3 tests/test-infra-webhook.py
python3 tests/test-secret-boundaries.py
python3 tests/test_firewall_rules.py
jq empty renovate.json
bash -n hosts/devenv/tools/update-network-firewall-rules.sh hosts/devenv/tools/release-infra.sh
nix-instantiate --parse <each changed Nix file>
python3 docs/checks/production-exposure.py  # plan only; no network
```

Fresh read-only review and parent caller review covered account, promotion and
migration boundaries. The parent caught and corrected impure-release output
inspection compatibility: checks now construct independent secret-free systems.
Migration review identified a missing-directory creation race; the final patch
rechecks canonical identity and full ancestry after creation, before staging.

Final `python3 modules/profiles/containers/tests/check_migration.py`, migration
Bash syntax and `git diff --check` passed. The tests confirm outside sentinels
remain unchanged for archive/checksum symlinks, rejects shared paths and four
injected directory-creation races before downtime, preserves normal export/import/
transfer behavior and cleanup, and rejects unknown/changed SSH keys before stops.
It also checks effective SSH options with `ssh -G` without connecting and exercises
trust-file provisioning using temporary files with ownership operations mocked.
This proves the synthetic trigger no longer reproduces, not a real production
migration or activated trust-file state.

All seven synthetic host builds were requested from an explicit tracked-source
copy under `/tmp`, with the denied secrets path excluded before any source copy.
The command used `nix build --offline --no-write-lock-file --no-link` for
`checks.x86_64-linux.{devenv,rp1,apps1,apps2,apps3,ai1,db1}`. It failed before
evaluation:

```text
cannot connect to socket at '/nix/var/nix/daemon-socket/socket': Operation not permitted
```

Thus no NixOS toplevel build, generated-tool execution, activated account test,
real migration, or deployed network test passed in this session. The existing
mesh namespace and built transfer-sandbox tests also remain unrun because their
required evaluated/built artifacts and runtime permissions are unavailable.
Synthetic/mocked tests do not establish activation or live network controls, and
synthetic host checks must never be deployed.
