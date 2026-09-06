# Technitium DNS Cluster Architecture

**Status:** Current deployment notes
**Last audited:** September 5, 2026

## Overview

Technitium DNS runs as two Docker containers:

- `dnsOne` on `apps1`
- `dnsTwo` on `apps2`

Both nodes expose DNS on their physical VLAN addresses and expose admin/cluster ports on the WireGuard mesh. Each host generates its own ACME certificate locally through the NixOS ACME module using Technitium DNS-01 credentials.

There is no implemented centralized certificate distribution service in the current source.

## Hosts And Addresses

| Host | Physical IP | Mesh IP | Container |
|------|-------------|---------|-----------|
| `apps1` | `10.1.11.2` | `10.255.0.3` | `dnsOne` |
| `apps2` | `10.1.11.3` | `10.255.0.4` | `dnsTwo` |
| `rp1` | `10.1.12.2`, `10.1.12.3`, `10.1.12.4` | `10.255.0.2` | NGINX reverse and stream proxy |

## Container Port Mappings

| Purpose | `dnsOne` on apps1 | `dnsTwo` on apps2 |
|---------|-------------------|-------------------|
| HTTP admin UI | `10.255.0.3:1026 -> 5380/tcp` | `10.255.0.4:1024 -> 5380/tcp` |
| HTTPS admin UI / cluster | `10.255.0.3:1027 -> 53443/tcp` | `10.255.0.4:1025 -> 53443/tcp` |
| DNS over mesh | `10.255.0.3:1028 -> 53/tcp+udp` | `10.255.0.4:1026 -> 53/tcp+udp` |
| DNS on VLAN | `10.1.11.2:53/tcp+udp` | `10.1.11.3:53/tcp+udp` |
| DoT on VLAN | `10.1.11.2:853/tcp+udp` | `10.1.11.3:853/tcp+udp` |
| DHCP on VLAN | `10.1.11.2:67/udp` | `10.1.11.3:67/udp` |

See [Mesh Network Port Reference](../mesh-network-ports.md) for the full allocation table.

## ACME Certificates

`apps1.nix` and `apps2.nix` both configure `security.acme`:

- ACME email: `admin@reinitialized.net`
- DNS provider: `technitium`
- credentials file: `config.secrets.acmeDns.file`
- DNS resolver: `10.255.0.3:1028`
- extra resolver flag: `--dns.resolvers=10.255.0.4:1026`
- output includes a PKCS#12 certificate with an empty PFX password

Each host defines one certificate:

| Host | Certificate name | Reload service |
|------|------------------|----------------|
| `apps1` | `one.dns.reinitialized.net` | `docker-dnsOne.service` |
| `apps2` | `two.dns.reinitialized.net` | `docker-dnsTwo.service` |

The ACME `postRun` hook exports the installed `fullchain.pem` and `key.pem`
with [OpenSSL PKCS#12](https://docs.openssl.org/3.6/man1/openssl-pkcs12/), then
atomically replaces `/var/lib/acme/<name>/cert.pfx` with mode `640` and owner
`acme:acme`. The empty PFX password preserves the existing Technitium setting;
filesystem permissions and the read-only container mount protect the private key.
The hook fails if export fails, leaving the previous PFX intact. It does not
search Lego's internal directory: that previously retained an expired PFX even
when the installed PEM certificate had renewed successfully.

When repairing an already stale PFX, run the evaluated `postRun` hook once as
`acme` after backing up the old file. A renewal with an unchanged leaf certificate
may skip the hook. Verify the served certificate matches the installed PEM on
one DNS node before touching the other node.

The DNS containers mount those directories read-only:

```nix
"/var/lib/acme/one.dns.reinitialized.net:/etc/dns/certs:ro"
"/var/lib/acme/two.dns.reinitialized.net:/etc/dns/certs:ro"
```

## rp1 Ingress

`rp1` uses the pinned stable NGINX package with stream support. The configuration
uses standard NGINX features, including TLS SNI routing and HTTP/3. The former
Angie package is marked insecure by the pinned Nixpkgs input because its security
updates are delayed.

### DNS Service

`rp1` listens on `10.1.12.2:53` and `10.1.12.3:53` for TCP and UDP DNS and stream-proxies to the physical Technitium backends:

- `10.1.11.2:53` for `dnsOne`
- `10.1.11.3:53` for `dnsTwo`

The stream blocks use `proxy_bind 10.1.12.3` so proxied public queries are distinguishable from rp1's own resolver traffic.

### DNS Admin UI

`rp1` provides:

- `10.1.12.2:53443 -> 10.255.0.3:1027`
- `10.1.12.3:53443 -> 10.255.0.4:1025`

HTTPS on shared port 443 uses SNI routing:

- `one.dns.reinitialized.net -> dnsOneUI`
- `two.dns.reinitialized.net -> dnsTwoUI`

The port 443 stream routes permit DNS administration only from RFC1918 source
addresses (`10.0.0.0/8`, `172.16.0.0/12`, and `192.168.0.0/16`). Connections from
other sources close without reaching either DNS backend, including unknown or
missing SNI. Private clients retain the existing DNS UI fallback. Public
`mail.reinitialized.net` SNI on `10.1.12.2:443` still reaches Stalwart.

The HTTP virtual hosts for `one.dns.reinitialized.net` and `two.dns.reinitialized.net`
only redirect to HTTPS and include the `internalOnly` nginx allow/deny block.
That HTTP configuration does not protect TLS passthrough; the stream source check
enforces the DNS administration boundary independently. The source address seen
by `rp1` must preserve the external client's address through upstream NAT.

An offline routing regression check runs these stream maps in the configured
NGINX binary with loopback test backends. It covers each private-network range,
public sources, unknown/missing SNI, and public mail routing:

```bash
nix eval --offline --raw --impure --expr \
  '(import ./hosts/rp1.nix { config = {}; pkgs = {}; }).services.nginx.streamConfig' \
  > /tmp/rp1-stream.conf
python3 docs/checks/rp1-dns-admin.py /path/to/nginx /tmp/rp1-stream.conf
```

## Recursion ACL

Both Technitium nodes should use `UseSpecifiedNetworkACL` for recursion with this ordered ACL:

```text
!10.1.12.3
172.16.0.0/24
10.0.0.0/8
```

Ordering matters. `10.1.12.3` is `rp1`'s DNS stream `proxy_bind` source for public DNS ingress and must remain denied before broader private-network allows. `172.16.0.0/24` is the OPNsense `wgAdmin` full-tunnel WireGuard client pool. `10.0.0.0/8` covers the internal VLAN hosts and `rp1`'s own resolver path.

Do not replace the narrow VPN entry with `172.16.0.0/12`; only the assigned WireGuard pool needs recursive resolver access.

## Secrets

Both DNS hosts require `secrets.acmeDns.file`.

Template shape:

```nix
secrets.acmeDns = {
  description = "Technitium DNS API token for ACME DNS-01 challenges";
  # Provision root-owned mode 0600 before activation. Keep values out of Nix.
  file = lib.mkDefault "/var/lib/service-secrets/acme-dns.env";
  keys = {};
};
```

The runtime file contains `TECHNITIUM_API_TOKEN` and
`TECHNITIUM_SERVER_BASE_URL=http://10.255.0.3:1026/`. Provision only the
credentials required by that host.

## Operational Checks

Check DNS directly:

```bash
dig @10.1.11.2 reinitialized.net +short
dig @10.1.11.3 reinitialized.net +short
dig @10.1.11.2 example.com +short
dig @10.1.11.3 example.com +short
```

From an OPNsense `wgAdmin` client, recursive lookups should also work against both Technitium VLAN addresses:

```bash
dig @10.1.11.2 example.com +short
dig @10.1.11.3 example.com +short
```

Check mesh admin endpoints:

```bash
curl --resolve one.dns.reinitialized.net:1027:10.255.0.3 https://one.dns.reinitialized.net:1027/
curl --resolve two.dns.reinitialized.net:1025:10.255.0.4 https://two.dns.reinitialized.net:1025/
```

Check generated PFX files on each DNS host:

```bash
ls -l /var/lib/acme/one.dns.reinitialized.net/cert.pfx
ls -l /var/lib/acme/two.dns.reinitialized.net/cert.pfx
```

Check container mappings:

```bash
docker ps --filter name=dnsOne
docker ps --filter name=dnsTwo
```

## Change Guidelines

- Keep ACME settings in `apps1.nix` and `apps2.nix` aligned unless intentionally diverging.
- Update `modules/secrets.example/apps1.nix` and `apps2.nix` if ACME credential keys change.
- Update [Mesh Network Port Reference](../mesh-network-ports.md) when any published port changes.
- Validate both affected host configs after DNS changes:

  ```bash
  nix build path:.#nixosConfigurations.apps1.config.system.build.toplevel
  nix build path:.#nixosConfigurations.apps2.config.system.build.toplevel
  nix build path:.#nixosConfigurations.rp1.config.system.build.toplevel
  ```

## Related Documentation

- [Mesh Network Module](../modules/meshNetwork.md)
- [Mesh Network Port Reference](../mesh-network-ports.md)
- [DNS Recursion Public Interface Investigation](../investigations/dns-recursion-public-interface-via-rp1.md)
- [OPNsense WireGuard Full-Tunnel DNS Failure](../investigations/opnsense-wireguard-full-tunnel-dns.md)
