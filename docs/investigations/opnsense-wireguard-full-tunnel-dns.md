# OPNsense WireGuard Full-Tunnel DNS Failure

**Date:** 2026-06-27

## Symptom

DNS became unreliable or failed when clients routed all traffic through the WireGuard VPN hosted on OPNsense.

## Router Findings

OPNsense has an assigned WireGuard interface:

| Item | Value |
|------|-------|
| Interface | `wg0` / `wgAdmin` |
| Filter ID | `opt1` |
| Tunnel address | `172.16.0.1/24` |
| Client pool | `172.16.0.0/24` |
| Active observed client | `M3-LT-003` at `172.16.0.4/32` |

Unbound was not the VPN resolver path. The WireGuard client traffic was using the Technitium DNS servers on the services VLAN.

Firewall logs showed DNS traffic from `172.16.0.4` passing through OPNsense toward both Technitium nodes:

```text
172.16.0.4 -> 10.1.11.2:53/udp
172.16.0.4 -> 10.1.11.3:53/udp
```

That means the router/firewall path was allowing DNS to the services VLAN. The issue was not a missing OPNsense pass rule for DNS.

## DNS Findings

Both Technitium nodes were healthy for allowed internal sources:

```bash
dig @10.1.11.2 example.com A +short
dig @10.1.11.3 example.com A +short
```

Both nodes were configured with this recursion policy:

```text
recursion = UseSpecifiedNetworkACL
recursionNetworkACL = !10.1.12.3,10.0.0.0/8
```

That policy was correct for the earlier public-recursion issue because `10.1.12.3` is `rp1`'s DNS stream `proxy_bind` source and must be denied. It was incomplete for VPN clients because the OPNsense WireGuard pool is `172.16.0.0/24`, not `10.0.0.0/8`.

## Root Cause

Full-tunnel WireGuard clients sent DNS queries to Technitium with source addresses in `172.16.0.0/24`. Technitium received those queries but denied recursion because the recursion ACL did not include that pool.

The failure pattern can be confusing because authoritative answers for local hosted zones may still work, while external names requiring recursion fail.

## Fix Applied

Updated both Technitium nodes to this ordered ACL:

```text
!10.1.12.3
172.16.0.0/24
10.0.0.0/8
```

The order preserves the open-resolver guard:

- `!10.1.12.3` denies recursive service to public DNS traffic proxied by `rp1`.
- `172.16.0.0/24` allows only the assigned OPNsense WireGuard client pool.
- `10.0.0.0/8` allows the internal VLAN fleet and `rp1`'s own resolver path.

Do not broaden this to `172.16.0.0/12`; the VPN pool is a single `/24`.

## Follow-Up

OPNsense currently reports the WireGuard peer generator default DNS as `10.1.11.2`. New generated client profiles should advertise both Technitium resolvers:

```text
10.1.11.2,10.1.11.3
```

The API account used during this investigation could read and reconfigure WireGuard but rejected server model writes, so update the peer-generator default through the OPNsense UI or with an API role that can save WireGuard server models.
