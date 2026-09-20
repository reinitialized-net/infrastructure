# Infrastructure access discovery — 2026-09-19

The [access CLI](../tools/infra-access/infra-access) and
[inventory](../tools/infra-access/inventory.json) provide harness-independent access.
Credentials are protected local files on devenv, outside the repository. See
[provisioning instructions](infrastructure-access.md#credential-provisioning).

## Current scope

Tailscale devices are excluded at the user's request. The CLI skips their probes
and refuses management operations, including known LAN aliases (`gs1`, `rinf`),
remote advertised-subnet devices, and the OPNsense Tailscale gateway itself.
Earlier discovery contacted these devices before the exclusion instruction; those
historical observations do not authorize further access. No Tailscale devices were
contacted during the dedicated-account enrollment pass. They are not credential
requests in this report.

## Newly established dedicated administrators

| System | Dedicated identity and access | Live verification |
| --- | --- | --- |
| hv1, 10.1.10.21 | `infraaccess` Unix/PAM user, dedicated SSH key, passwordless sudo; `infraaccess@pam!automation` API token with Administrator at `/` | SSH login, sudo UID 0, privileged temporary-file create/read/delete; API permission read and accepted same-value write to its own account comment |
| pbs1, 10.1.10.22:8007 | `infraaccess` Unix/PAM user, dedicated SSH key, passwordless sudo; `infraaccess@pam!automation` token with Admin at `/` | Same host write test; API system status HTTP 200 and accepted same-value write to its own account comment |
| hv1 iDRAC, 10.1.10.41 | `infraaccess`, previously unused slot 3, full Administrator | IPMI password verification; dedicated Redfish login, Administrator role, own-account enabled write/readback |
| PBS iDRAC, 10.1.10.42 | `infraaccess`, previously unused slot 3, full Administrator | Dedicated Redfish login, Administrator role, own-account enabled write/readback; system identifies as PowerEdge T430 |
| UniFi, unifi.in.reinitialized.net | `infraaccess`, global superadmin | Fresh dedicated login and `/api/self` reports `is_super: true`; supported superadmin operation accepted under its own login |

The supplied existing accounts were used for bootstrap only. No existing admin
password was reset, and their permissions were not changed. hv1 iDRAC's original
slot 2 configuration was compared before and after the privilege grant and was
unchanged. PBS iDRAC slot 2 username, role and enabled state also match the
pre-enrollment snapshot. Existing PBS backup-token permissions were preserved.

hv1 iDRAC enrollment used local IPMI to create the new account, then local RACADM
to grant `iDRAC.Users.3.Privilege=0x1ff`. IPMI Administrator alone left Dell's web
privileges at zero. Temporarily extracted official Dell packages needed their
normal HAPI configuration before local RACADM could operate; the staging tree and
temporary `/opt/dell` symlink were removed. No BMC reset or server power action was
needed. Device-side accounts and tokens persist independently of the harness.

`sudo` was installed on hv1 and pbs1, and a validated mode-0440
`/etc/sudoers.d/90-infraaccess` grants the dedicated user full administration.
The dedicated SSH private key and generated account passwords remain outside Git.
API keys/tokens are used on Proxmox and PBS; UniFi uses a dedicated authenticated
session because a supported API-key creation operation was not established.

## Previously verified local access

These paths were established before the dedicated-account instruction and were
not rewritten during this enrollment pass. Existing credentials remain in protected
profiles; they are not newly created dedicated identities.

| Systems | Administrative path and evidence |
| --- | --- |
| devenv, rp1, apps1, apps2, apps3, db1 | SSH plus passwordless sudo; privileged temporary-file create/read/delete |
| sw2, 10.1.10.3 | UniFi US24P250; controller-managed SSH account executes as UID 0; temporary-file create/read/delete |
| wap1, 10.1.10.11 | UniFi UAL6; same SSH/write qualification |
| cortex, hv1 VM 208 | QEMU guest execution as root; temporary-file create/read/delete; transport rechecked through dedicated hv1 sudo account |
| WINSVCS1, hv1 VM 301 | QEMU guest execution as SYSTEM; temporary-file create/read/delete |
| Cameras 10.1.14.2/.3/.4/.14 | ONVIF Administrator credentials; hostname same-value write/readback. Models C120 (.2/.3), C121 (.4/.14) |

WINSVCS1 owns 10.1.10.254, 10.1.11.254, 10.1.12.6, 10.1.13.254,
10.1.14.254 and 10.1.200.254: one server, not six credential requests.
Shell access does not prove every application API, and ONVIF does not cover every
proprietary camera/cloud feature. Same-value API writes prove acceptance, not an
observed transition to a different setting.

## Remaining local access gaps

| Target | Confirmed evidence | Needed |
| --- | --- | --- |
| sw1 / RouterOS, 10.1.10.2 | SSH, Telnet, WebFig, Winbox and RouterOS API listeners reachable. **Blank `admin` password rejected by SSH, API and Telnet**; blank `rnetadmin` rejected by API. Existing device password and newly supplied UniFi controller login also rejected. API TLS handshake fails; plaintext API was additionally checked as authorized. No reset or account change performed. | Correct existing full-permission username/password or authorized key, then create a dedicated full-permission account. It does not currently accept the tested passwordless logins. |
| Windows at 10.1.13.10 | SMB/RDP reachable; SSH absent; no matching admin credential available. This conflicts with the repository's planned ai1 address. | Machine/domain identity and administrator login or another enabled management path. No deployment attempted. |
| CEO-LT-017 (.13.4), CEO-LT-024 (.13.11), CEL-LT-031 (.13.27) | Present in prior ARP/UniFi inventory; no tested management listener. | Enabled management service and account if these are still in scope and online. |
| Historical .200.72 (`sysrescue`) and .200.73 | DHCP history only; no tested management listener responded. | Confirm current presence before treating as credential failures. |

No new credentials are requested for PBS, either iDRAC, or UniFi: dedicated access
is now established. Do not send credentials for excluded Tailscale endpoints.

## Credential handling and earlier changes

Private credentials/SSH host keys are under `~/.config/infra-access/`; private
audit and enrollment evidence are under `~/.local/state/infra-access/`.
Generated dedicated credentials are not embedded in scripts, inventory or Nix
configuration. Bootstrap-only supplied-password profiles were deleted after
dedicated access was verified. HTTPS certificate verification is disabled only for configured
endpoints as authorized; SSH retains changed-host-key detection.

Before the latest instruction, discovery added an existing public key to OPNsense
root and created hv1's `root@pam!infra-access` token. Those earlier bootstrap
artifacts were preserved; the active hv1 inventory now uses the dedicated
`infraaccess` account/token. OPNsense is excluded from subsequent access. No
existing administrator was modified during this dedicated-account enrollment.

## Validation and limits

- 22 tool tests passed, including real HTTPS, credential isolation/redaction,
  authentication failure handling, UniFi session handling, excluded-target refusal
  without network/credential access, and privileged guest routing.
- New dedicated identities were independently authenticated; administrative writes
  and readbacks are described above. No firmware update, power action, network
  configuration change, NixOS deployment, controller database modification, commit
  or push was performed.
- Discovery covered known local management/services/trusted/untrusted/testing
  networks and the actual DMZ /29. Sleeping devices, UDP-only management,
  unadvertised networks and short probe timeouts can hide endpoints. This is a
  bounded qualification, not proof every physical device has been found.
- Repository files were compared against provisioned secret values with no matches;
  credential ownership/modes and `git diff --check` passed.
- No NixOS module or flake input changed; host rebuilds are not applicable.
