# Matrix Federation Failure: Cannot Find or Message @evan:ins4.xyz

## Symptoms

1. **Cannot find @evan:ins4.xyz** — Searching for the user or starting a DM fails silently
2. **@me:mrparker.dev works perfectly** — Can find, add, and message without issues
3. **Group chat media breakage** — When @me:mrparker.dev creates a group with both @me:reinitialized.me and @evan:ins4.xyz:
   - Images from mrparker.dev stop displaying for the local user
   - After mrparker.dev sends a text message, everything syncs up between all three users
   - This pattern is repeatable

## Root Cause

`CONDUWUIT_TRUSTED_SERVERS` was set to `[]` (empty), leaving the Tuwunel homeserver with **no key notary fallback** for signing key verification during federation.

### How Matrix federation key verification works

When server A wants to federate with server B:

1. **Direct key fetch**: Server A requests B's signing keys at `GET https://B/_matrix/key/v2/server`
2. **Notary fallback**: If direct fetch fails, server A asks a trusted key notary (e.g., `matrix.org`) to provide B's keys via `GET https://notary/_matrix/key/v2/query/{serverName}`
3. If both fail → federation with server B is impossible (can't verify message signatures)

### Why mrparker.dev works but ins4.xyz doesn't

- **mrparker.dev**: Their federation key endpoint is directly reachable from our Tuwunel container → direct key fetch succeeds → federation works
- **ins4.xyz**: Their server is behind Cloudflare Tunnel (documented in `matrix-federation-signing-key-fetch-failure.md`), which makes their key endpoint unreachable via direct fetch → with no key notary configured, there's no fallback → federation fails entirely

### Why the group chat behavior occurs

1. mrparker.dev's server creates the room and can federate with both reinitialized.me and ins4.xyz (their server likely has `matrix.org` as a trusted key notary)
2. Our server (`reinitialized.me`) receives room events from mrparker.dev (we can verify their keys) and from ins4.xyz (we CANNOT verify their keys)
3. Events from ins4.xyz are rejected/ignored because we can't verify their signatures → media from that session breaks
4. When mrparker.dev sends a message, their server propagates state updates that both sides can verify through mrparker.dev's signatures → this acts as an indirect relay, temporarily syncing the room state

## Steps Taken to Investigate

1. Reviewed current Tuwunel configuration in `modules/secrets/apps3.nix`:
   - `CONDUWUIT_SERVER_NAME = "reinitialized.me"` (changed from previous `matrix.reinitialized.net`)
   - `CONDUWUIT_ALLOW_FEDERATION = "true"` (federation is enabled)
   - `CONDUWUIT_TRUSTED_SERVERS = '[]'` ← **root cause: empty, no key notary**
2. Verified rp1 nginx configuration:
   - `reinitialized.me` virtualhost serves well-known endpoints and proxies `/_matrix` to Tuwunel
   - No `internalOnly` restriction, ports 80/443 open to `0.0.0.0/0`
   - Federation traffic is not blocked by firewall rules
3. Reviewed previous investigation (`matrix-federation-signing-key-fetch-failure.md`):
   - Confirmed our federation endpoints are publicly accessible (Matrix Federation Tester passes)
   - ins4.xyz is behind Cloudflare Tunnel, which limits direct key endpoint accessibility
   - Previous investigation incorrectly characterized `trusted_servers` as a "federation allowlist" — it's actually a **key notary** list
4. Cross-referenced symptoms with Matrix spec:
   - The pattern of "works through a third server but not directly" is diagnostic of signing key verification failure
   - Key notary (trusted_servers) is the standard fallback mechanism

## Changes Made

### 1. Added `matrix.org` as trusted key notary server

**File:** `modules/secrets/apps3.nix` and `modules/secrets.example/apps3.nix`

```nix
# Before
CONDUWUIT_TRUSTED_SERVERS = ''[]'';

# After
CONDUWUIT_TRUSTED_SERVERS = ''["matrix.org"]'';
```

This restores the default Tuwunel behavior. When direct signing key fetch from a remote server fails, our server will ask `matrix.org` to provide the keys. Since `matrix.org` can reach most federation endpoints (including those behind Cloudflare), this provides a reliable fallback.

### 2. Updated example secrets

**File:** `modules/secrets.example/apps3.nix`

- Changed `CONDUWUIT_SERVER_NAME` from `matrix.reinitialized.net` to `reinitialized.me` (matching actual value)
- Changed `CONDUWUIT_ALLOW_FEDERATION` from `false` to `true` (matching actual value)
- Changed `CONDUWUIT_TRUSTED_SERVERS` from `[]` to `["matrix.org"]`

### 3. Updated architecture documentation

**File:** `docs/architecture/matrix-setup.md`

- Updated all references from `matrix.reinitialized.net` to `reinitialized.me`
- Updated homeserver name from Conduwuit to Tuwunel throughout
- Corrected federation status (enabled, not disabled)
- Updated trusted_servers documentation
- Fixed well-known endpoint documentation to reflect current URLs

### 4. Corrected previous investigation

**File:** `docs/investigations/matrix-federation-signing-key-fetch-failure.md`

- Added correction note about `trusted_servers` not being a federation allowlist
- Updated resolution guidance with correct server name
- Added cross-reference to this investigation

## Remaining Issue: NAT Hairpin Failure (inbound federation from ins4.xyz blocked)

After deploying the trusted_servers fix and rebuilding apps3, further testing revealed a second issue preventing full bidirectional federation.

**Critical context**: `ins4.xyz` and `reinitialized.me` share the same physical infrastructure:
- `matrix.ins4.xyz` runs directly on `10.1.12.5` (VLAN 12) — manages its own DNS
- `reinitialized.me` runs via rp1 at `10.1.12.4` (VLAN 12) — uses Technitium DNS (which resolves internal domains to LAN IPs)

### Outbound federation (us → ins4.xyz): WORKING

```
$ curl -s https://reinitialized.me/_matrix/client/v3/profile/%40evan%3Ains4.xyz
{"avatar_url":"mxc://ins4.xyz/BETTsM6oYLclyt4FUrCcnZPhf2PfadF1","displayname":"evan"}
```

Our Tuwunel (on apps3, VLAN 11) resolves `matrix.ins4.xyz` via Technitium DNS → Cloudflare IPs (104.21.61.215, 172.67.215.104) → works because Cloudflare proxies to the origin.

### Inbound federation (ins4.xyz → us): BLOCKED

```
$ curl -s --max-time 15 'https://matrix.ins4.xyz/_matrix/client/v3/profile/%40me%3Areinitialized.me'
# HANGS — no response until timeout
```

### Root cause: NAT hairpin failure on VLAN 12

ins4.xyz's server uses its own DNS (not Technitium), so `reinitialized.me` resolves to the **public IP** `47.190.182.79`. When a host on VLAN 12 (where the router performs NAT) tries to connect to the public IP, the traffic must "hairpin" through the router — go out, get NATted, and come back in. This router does not support NAT hairpin (or it is disabled), so the TCP connection silently hangs.

**Verification tests:**

| Source | Destination | Result |
|--------|------------|--------|
| VLAN 12 (rp1: `10.1.12.2`) → `47.190.182.79:443` | **Timeout** (exit code 124) — NAT hairpin fails |
| VLAN 200 (devenv: `10.1.200.2`) → `47.190.182.79:443` | **Works** (TCP connected, got response) |
| VLAN 12 (rp1) → `10.1.12.4:443` (local) | **Works** (normal nginx) |
| External (Matrix Federation Tester) → `47.190.182.79:443` | **Works** |

The key difference: VLAN 200 can hairpin through the router, but VLAN 12 cannot. ins4.xyz at `10.1.12.5` is on the same broken VLAN, so its outbound requests to `47.190.182.79` never complete.

Meanwhile, ins4.xyz CAN reach Cloudflare-proxied servers (mrparker.dev, matrix.org) because those resolve to external Cloudflare IPs — the traffic leaves the network normally without needing to hairpin.

## Resolution

### Our side (complete)

1. Added `matrix.org` as trusted key notary (`CONDUWUIT_TRUSTED_SERVERS = ["matrix.org"]`)
2. Updated example secrets, architecture docs, and previous investigation
3. Verified outbound federation to ins4.xyz works (profile lookup succeeds)
4. Deployed to apps3 via `rebuildHost apps3`

### ins4.xyz side (required for bidirectional federation)

The ins4.xyz operator needs to add a **DNS override** in their DNS server so that `reinitialized.me` resolves to the local VLAN IP instead of the public IP:

```
reinitialized.me  A  10.1.12.4
```

This way, ins4.xyz's Tuwunel will connect to rp1 directly over VLAN 12 instead of trying to hairpin through the router via the public IP.

**Diagnostic commands for the ins4.xyz operator:**
```bash
# Verify DNS resolution (should show 47.190.182.79 currently)
dig reinitialized.me A +short

# After adding the override, should show 10.1.12.4
dig reinitialized.me A +short

# Test connectivity (should work after DNS override)
curl -s --max-time 10 https://reinitialized.me/_matrix/key/v2/server
```
