# DNS Recursion Accessible from Public Interface via rp1

## Problem

Public internet clients could perform recursive DNS queries against Technitium DNS (apps1/apps2), despite Technitium being configured to only allow recursion from private IP ranges.

## Root Cause

rp1's nginx stream proxy for DNS (port 53) forwards queries to Technitium at the physical interface IPs (`10.1.11.2:53` for apps1, `10.1.11.3:53` for apps2). Since nginx stream is a Layer 4 proxy, it terminates the original connection and opens a new one to the upstream — the source IP seen by Technitium is rp1's own VLAN 12 address (`10.1.12.2`), not the original client's public IP.

Because `10.1.12.2` falls within the `10.0.0.0/8` private range, Technitium's recursion ACL treated all proxied queries as internal, allowing full recursion for any public client.

The DNS protocol (especially UDP) does not support proxy protocol, so preserving the original client IP through the nginx stream proxy is not possible.

**Traffic flow (before fix):**
```
Public Client (203.0.113.x) → rp1 (10.1.12.2:53) → nginx stream → apps1 (10.1.11.2:53)
                                                      Source IP: 10.1.12.2 (private!)
                                                      → Technitium allows recursion ✗
```

## Steps to Identify

1. Observed that DNS recursion was functional from the public interface
2. Reviewed rp1's nginx stream configuration — DNS upstreams pointed to physical IPs
3. Identified that nginx stream proxy performs SNAT (source IP becomes rp1's IP)
4. Confirmed Technitium's recursion ACL allows all private IPs, which includes rp1's VLAN 12 address
5. The DNS protocol does not support proxy protocol, so preserving the client IP through the nginx proxy is not possible

## Previous Fix Attempt (Reverted)

Initially, the DNS upstream was changed to route through WireGuard mesh IPs (`10.255.0.3:1028`, `10.255.0.4:1026`) so Technitium would see rp1's mesh IP (`10.255.0.2`) as the source. While this correctly distinguished proxied traffic, it caused two problems:

1. **DNS cluster sync broke** — Cluster replication relies on the DNS nodes communicating over their physical/cluster ports. Routing DNS queries through mesh altered the traffic paths in ways that disrupted cluster synchronization.
2. **Private IPs returned externally** — Technitium began returning private/internal IP addresses in DNS responses to external queries, breaking public access to services.

The mesh routing approach was reverted back to physical IP upstreams.

## Fix Applied

The fix uses a two-layer approach: deterministic source IP binding in nginx + Technitium ACL deny rules.

### Infrastructure Change (rp1.nix)

1. **Added `proxy_bind 10.1.12.3`** to both DNS stream proxy server blocks. This ensures all proxied DNS traffic uses rp1's **secondary** IP (`10.1.12.3`) as the source when connecting to Technitium. Using the secondary IP (instead of the primary `10.1.12.2`) distinguishes proxied public traffic from rp1's own system resolver queries, which originate from the primary IP.

2. **DNS upstreams remain on physical IPs** (`10.1.11.2:53`, `10.1.11.3:53`). This preserves correct DNS cluster sync behavior and ensures Technitium returns the correct (public) records for external queries.

**Traffic flow (after fix):**
```
Public Client → rp1 (10.1.12.2:53) → nginx stream (proxy_bind 10.1.12.3) → apps1 (10.1.11.2:53)
                                                      Source IP: 10.1.12.3
                                                      → Technitium ACL denies recursion ✓

Public Client → rp1 (10.1.12.3:53) → nginx stream (proxy_bind 10.1.12.3) → apps2 (10.1.11.3:53)
                                                      Source IP: 10.1.12.3
                                                      → Technitium ACL denies recursion ✓

Internal Client (10.1.11.x) → apps1 (10.1.11.2:53) direct
                                Source IP: 10.1.11.x (private)
                                → Technitium ACL allows recursion ✓

rp1 system resolver → apps1 (10.1.11.2:53) direct (not via nginx)
                       Source IP: 10.1.12.2 (primary IP, not proxy_bind IP)
                       → Technitium ACL allows recursion (matches 10.0.0.0/8) ✓
```

### Required Technitium Configuration

Configure Technitium's recursion ACL on **both cluster nodes** (one.dns and two.dns):

1. Open Technitium web UI → **Settings** → **Recursion**
2. Select **Use Specified Network Access Control List (ACL)**
3. Set the ACL entries in this exact order (Technitium processes top to bottom, first match wins):
   ```
   !10.1.12.3/32
   10.0.0.0/8
   ```
4. Save and apply on both DNS cluster nodes

**ACL logic:**
- `!10.1.12.3/32` — Deny recursion from rp1's proxy-bind IP only. All proxied public DNS traffic uses this source IP due to `proxy_bind 10.1.12.3`.
- `10.0.0.0/8` — Allow recursion for all other private 10.x clients, including rp1's own system resolver (source `10.1.12.2`), internal hosts, and Docker containers.
- Default policy (no match) — Deny all except loopback. This blocks recursion for any other non-private source.

**Important:** The deny entry (`!`) MUST be listed BEFORE the allow entry. Technitium processes the ACL in listed order and uses the first match. If `10.0.0.0/8` appears first, it would match and allow recursion for 10.1.12.3 before the deny rule is ever checked.

## Follow-up: rp1 System Resolver Denied Recursion

### Problem

After the original fix, rp1's own system DNS resolution stopped working for recursive queries. The system resolver (`dns = ["10.1.11.2" "10.1.11.3"]` in systemd-networkd) sends queries directly to Technitium with source IP `10.1.12.2` — the same IP used by `proxy_bind`. The overly broad ACL `!10.1.12.0/29` denied recursion for **all** traffic from VLAN 12, including rp1's legitimate system queries.

### Root Cause

The original fix used `proxy_bind 10.1.12.2` (rp1's primary IP) and denied the entire `/29` subnet. Since rp1's system resolver also originates from `10.1.12.2`, there was no way for Technitium to distinguish proxied WAN traffic from rp1's own queries.

### Fix

1. Changed `proxy_bind` from `10.1.12.2` to `10.1.12.3` (rp1's secondary IP) in the nginx stream DNS server blocks.
2. Narrowed the Technitium ACL deny rule from `!10.1.12.0/29` to `!10.1.12.3/32`.

This separates the two traffic sources:
- **Proxied public queries**: source `10.1.12.3` (via `proxy_bind`) → denied by `!10.1.12.3/32`
- **rp1's own system resolver**: source `10.1.12.2` (kernel default primary IP) → allowed by `10.0.0.0/8`

## Key Insight

Rather than changing the DNS routing path (which introduced cluster sync issues), the fix keeps the proven physical IP routing and uses Technitium's network ACL to deny recursion from the specific source address that rp1's proxy produces. The `proxy_bind` directive uses rp1's **secondary** IP (`10.1.12.3`) rather than the primary (`10.1.12.2`), which allows the ACL to distinguish proxied public traffic from rp1's own legitimate system DNS queries. The narrow `/32` deny rule targets only the proxy-bind IP, so rp1's system resolver (using the primary IP `10.1.12.2`) gets recursion while proxied WAN queries do not.
