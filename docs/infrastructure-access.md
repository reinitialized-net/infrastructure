# Harness-independent infrastructure access

Run `./tools/infra-access/infra-access` from any harness with Python 3 and OpenSSH.
The [inventory](../tools/infra-access/inventory.json) contains endpoints and profile
names only. [Discovery and qualification](infrastructure-access-discovery-2026-09-19.md)
records which identities actually authenticated and accepted administrative writes.

## Scope

Leave Tailscale devices alone. Inventory entries marked `excluded` cannot be used
for discovery, SSH, APIs, ONVIF or guest execution. This includes known LAN aliases
of Tailscale peers and the OPNsense Tailscale gateway itself. Raw tailnet IPv4/IPv6
addresses and `.ts.net` endpoints are also refused. Preserve these exclusions when
extending inventory. This is an inventory guard, not a sandbox around arbitrary
remote shell commands; do not tunnel or invoke commands against excluded devices.

Create dedicated administrative identities when enrolling devices. Existing
administrators may bootstrap those identities; do not reset or change them.
Current dedicated username is `infraaccess` on hv1, pbs1, both iDRACs and UniFi.
Proxmox and PBS use separate administrator API tokens belonging to that identity.
Previously established fleet/device identities remain recorded in the inventory.

## Usage

```bash
./tools/infra-access/infra-access list
./tools/infra-access/infra-access discover
./tools/infra-access/infra-access ssh hv1 'sudo -n id -u'
./tools/infra-access/infra-access api hv1 GET /api2/json/nodes
./tools/infra-access/infra-access api pbs1 GET /api2/json/nodes/localhost/status
./tools/infra-access/infra-access api unifi GET /api/self
./tools/infra-access/infra-access api idrac-41 GET /redfish/v1/Systems/System.Embedded.1
./tools/infra-access/infra-access guest cortex -- id
./tools/infra-access/infra-access onvif camera-10-1-14-2 tools/infra-access/requests/GetUsers.xml
```

API writes support POST/PUT/PATCH/DELETE and JSON `--body-file FILE` or
`--body-file -` for stdin. There is no additional approval prompt. Pass secrets
through protected files or stdin, never command arguments. API output is redacted;
`--output /protected/path/response.json` saves unredacted JSON in a new mode-0600
file outside the checkout. SSH and guest output is **unfiltered**: avoid commands
that print credentials or full device configurations.

UniFi uses a fresh, in-memory authenticated cookie session per command, with CSRF
header forwarding when supplied. No supported API-key enrollment operation was
established during discovery; its dedicated superadmin session covers management
operations. PBS and Proxmox use API tokens. iDRAC uses dedicated Basic credentials
over HTTPS. Specific self-signed HTTPS devices opt out of certificate verification
in inventory, as authorized. SSH still checks previously enrolled host keys.

## Credential provisioning

Credentials live in `~/.config/infra-access/`, owned by the invoking OS user, with
mode 0600 (or read-only 0400); the directory should be 0700. Nothing secret belongs
inside this repository, even in ignored directories. Set `INFRA_ACCESS_SECRETS` to
use another protected directory. This setting applies to credential profiles;
SSH key/known-host paths are explicit inventory fields.

Enroll values using hidden terminal prompts:

```bash
install -d -m 700 ~/.config/infra-access
./tools/infra-access/infra-access credential hv1-api proxmox
./tools/infra-access/infra-access credential pbs1-api proxmox-backup
./tools/infra-access/infra-access credential idrac-hv1-admin basic
./tools/infra-access/infra-access credential idrac-pbs1-admin basic
./tools/infra-access/infra-access credential unifi-admin unifi-session
```

Enrollment refuses overwriting files. Profiles are JSON with a `type` and:

| Type | Fields |
| --- | --- |
| `basic`, `unifi-session`, `ssh-password` | `username`, `password` |
| `proxmox`, `proxmox-backup` | `token_id`, `secret` |
| `header` | `header` (`Authorization` or `X-API-Key`), `value` |

On another machine, clone the repository, install Python 3/OpenSSH, and securely
transfer the needed profiles from devenv over an already trusted encrypted channel.
Transfer `dedicated-ssh-key` and the infrastructure `known_hosts` file to the paths
referenced in inventory; preserve key permissions. Alternatively generate a new
per-machine SSH key and add its public key to the **dedicated** accounts using
existing authorized access. Other fleet entries reference existing `~/.ssh/` keys;
provision those separately or use a local inventory copy with `--inventory PATH`.
Do not enroll changed host keys without checking their identity through a trusted
management path. Test `id`, API identity/permissions and a small reversible write.

Audit metadata lives in `~/.local/state/infra-access/audit.jsonl`, or
`INFRA_ACCESS_STATE`. It records device, operation, time and outcome without
request bodies, commands, URLs or responses. Discovery does not authenticate and
is not proof of administrative access.

## Revocation and validation

Revoke a dedicated API token and its ACL in Proxmox/PBS; disable or remove the
corresponding dedicated account when all of its access should end. For host SSH,
remove that account's authorized key and its `/etc/sudoers.d/90-infraaccess` rule.
For iDRAC, the dedicated account occupies slot 3; preserve the existing slot 2.
For UniFi, remove only `infraaccess` through administrator management. Keep local
protected profiles synchronized after rotation; deleting a profile alone does not
revoke the device credential.

Run `python3 tests/test-infra-access.py`; set `OPENSSL` if it is not on PATH to
include the real HTTPS fixture. No NixOS configuration is changed by this CLI.
