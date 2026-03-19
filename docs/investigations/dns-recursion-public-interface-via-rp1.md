# DNS Recursion Accessible from Public Interface via rp1

## Problem

Public internet clients could perform recursive DNS queries against Technitium DNS (apps1/apps2), despite Technitium being configured to only allow recursion from private IP ranges.

## Root Cause

rp1's nginx stream proxy for DNS (port 53) forwarded queries to Technitium at the physical interface IPs (`10.1.11.2:53` for apps1, `10.1.11.3:53` for apps2). Since nginx stream is a Layer 4 proxy, it terminates the original connection and opens a new one to the upstream — the source IP seen by Technitium is rp1's own VLAN 12 address (`10.1.12.2`), not the original client's public IP.

Because `10.1.12.2` falls within the `10.0.0.0/8` private range, Technitium's recursion ACL treated all proxied queries as internal, allowing full recursion for any public client.

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
5. The DNS protocol (especially UDP) does not support proxy protocol, so preserving the client IP through the nginx proxy is not possible

## Fix Applied

### Infrastructure Change (rp1.nix)

Changed the DNS stream proxy upstreams from physical network IPs to WireGuard mesh network IPs:

| Upstream | Before (physical) | After (mesh) |
|---|---|---|
| `dnsOneService` | `10.1.11.2:53` | `10.255.0.3:1028` |
| `dnsTwoService` | `10.1.11.3:53` | `10.255.0.4:1026` |

This routes all rp1-proxied DNS through the mesh, so Technitium sees rp1's mesh IP (`10.255.0.2`) as the source instead of its physical VLAN 12 IP.

**Traffic flow (after fix):**
```
Public Client → rp1 (10.1.12.2:53) → nginx stream → mesh → apps1 (10.255.0.3:1028)
                                                      Source IP: 10.255.0.2 (mesh)
                                                      → Technitium denies recursion ✓

Internal Client (10.1.11.x) → apps1 (10.1.11.2:53) direct
                                Source IP: 10.1.11.x (private)
                                → Technitium allows recursion ✓

rp1 own DNS queries → apps1 (10.1.11.2:53) direct (via system resolver)
                       Source IP: 10.1.12.2 (private)
                       → Technitium allows recursion ✓
```

### Required Technitium Configuration

After deploying the infrastructure change, configure Technitium to deny recursion from rp1's mesh IP:

1. Open Technitium web UI (one.dns or two.dns)
2. Go to **Settings** → **General** → **Recursion**
3. Set recursion to **Use Specified Networks** or **Allow Only For Private Networks**
4. Add `10.255.0.2/32` (rp1's mesh IP) to the **Denied Networks** list
5. Save and apply on both DNS cluster nodes

This ensures Technitium serves authoritative-only responses for queries arriving from rp1 (public-proxied traffic) while maintaining full recursion for direct internal clients.

## Key Insight

The WireGuard mesh network creates a distinct identity for rp1-proxied traffic (`10.255.0.2`) versus direct physical network traffic (`10.1.12.2`). This separation was already in use for other services (DNS UI, Stalwart, Hudu) and is the natural pattern for distinguishing proxy-originated traffic from direct client connections.
