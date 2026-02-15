# Architecture Decision: Stalwart Native ACME TLS

**Date:** 2026-02-15  
**Status:** Implemented  
**Scope:** rp1 (reverse proxy), apps1 (Stalwart host)

## Context

Stalwart Mail Server on apps1 serves all mail protocols (SMTP, IMAP, SMTPS, IMAPS, POP3S, Submission, Sieve) and a web management UI, all exposed through rp1's nginx reverse proxy.

Previously, **all TLS termination** was handled by nginx on rp1:
- The web UI (HTTPS on 443) was terminated via a stream SSL block (`127.0.0.1:8443`), with plain HTTP forwarded to Stalwart's port 8080
- Mail protocol ports (465, 993, 995) were TCP-passthrough to Stalwart, but Stalwart did not perform TLS on them — they were effectively plaintext between rp1 and Stalwart
- STARTTLS on ports 25, 143, 587 was not properly supported since nginx stream can't upgrade plaintext connections to TLS mid-stream

This meant:
1. **No native STARTTLS** — clients connecting on port 587 (submission) couldn't upgrade to TLS because nginx was just TCP-proxying
2. **Certificate management split** — rp1 managed the cert via `security.acme` DNS-01, but Stalwart had no awareness of certificates
3. **Complex stream config** — SNI routing → local SSL termination → PROXY protocol → Stalwart added multiple failure points

## Decision

Migrate TLS certificate management to **Stalwart's built-in ACME support** using the **HTTP-01** challenge type. rp1 becomes a plain TCP passthrough (with PROXY protocol) for all Stalwart traffic. Stalwart manages its own Let's Encrypt certificate for `mail.reinitialized.net`.

## Options Considered

### Option 1: Keep nginx SSL termination (status quo)
- **Pros:** Centralized cert management; familiar pattern; works for web UI
- **Cons:** No STARTTLS support; complex stream config; Stalwart unaware of certs; split responsibility between rp1 and Stalwart for mail TLS

### Option 2: Stalwart native ACME with DNS-01
- **Pros:** Supports wildcards; no port 80 dependency
- **Cons:** Stalwart's built-in ACME DNS-01 only supports Cloudflare and RFC2136 (TSIG) providers. Our DNS is Technitium, which uses API tokens — **not supported by Stalwart's ACME DNS providers**

### Option 3: Stalwart native ACME with TLS-ALPN-01
- **Pros:** Clean; no port 80 needed; works on port 443
- **Cons:** Stalwart docs explicitly state TLS-ALPN-01 **does not work behind reverse proxies**. Since rp1 sits in front of Stalwart, this is ruled out.

### Option 4: Stalwart native ACME with HTTP-01 (chosen)
- **Pros:** Simple; well-supported; Stalwart handles everything; proper STARTTLS; no API token dependency
- **Cons:** Requires port 80 HTTP path to reach Stalwart; no wildcard cert support (acceptable for single domain)

## Implementation

### ACME Challenge Flow (HTTP-01)
```
Let's Encrypt → http://mail.reinitialized.net/.well-known/acme-challenge/<TOKEN>
             → rp1 (10.1.12.2:80, nginx virtualHost)
             → proxy_pass http://127.0.0.1:8480/.well-known/acme-challenge/
             → local stream relay (adds PROXY protocol header)
             → stalwartOneHttp (10.255.0.3:1029 → container port 8080)
             → Stalwart responds with ACME token
```

**Why the local relay?** Stalwart's `server.proxy.trusted-networks = "10.255.0.2/32"` means
ALL connections from rp1's mesh IP must include PROXY protocol headers. A plain HTTP
`proxy_pass` cannot inject PROXY protocol, so a stream relay at `127.0.0.1:8480` is used
to add the PROXY protocol header before forwarding to Stalwart.

### HTTPS/Mail Traffic Flow (post-migration)
```
Client → mail.reinitialized.net:443 (HTTPS)
      → rp1 (10.1.12.2:443, stream SNI routing)
      → mailProxyProtocol upstream (127.0.0.1:8443, local relay)
      → adds proxy_protocol → stalwartOneHttps (10.255.0.3:1042 → container 443)
      → Stalwart terminates TLS using native ACME cert

Client → mail.reinitialized.net:993 (IMAPS)
      → rp1 (10.1.12.2:993, stream)
      → TCP passthrough with proxy_protocol → stalwartOneImaps (10.255.0.3:1034)
      → Stalwart terminates TLS using native ACME cert

Client → mail.reinitialized.net:587 (Submission + STARTTLS)
      → rp1 (10.1.12.2:587, stream)
      → TCP passthrough with proxy_protocol → stalwartOneSubmission (10.255.0.3:1033)
      → Stalwart handles STARTTLS upgrade using native ACME cert
```

**Why the local HTTPS relay?** The `10.1.12.2:443` SNI routing server block is shared
between mail traffic and DNS admin UI traffic. DNS UI backends do NOT expect PROXY protocol
headers, so `proxy_protocol on` cannot be added to the shared block. Instead, mail traffic
is routed to a local relay at `127.0.0.1:8443` that selectively adds PROXY protocol before
forwarding to Stalwart's HTTPS listener.

### Changes to rp1.nix
1. **Removed** `security.acme.certs."mail.reinitialized.net"` — Stalwart owns the cert now
2. **Replaced** stream SSL termination block (`127.0.0.1:8443 ssl`) with a plain TCP PROXY protocol relay (`127.0.0.1:8443` without SSL) — still needed because the `10.1.12.2:443` SNI routing server block is shared with DNS UI traffic that must NOT receive PROXY protocol headers
3. **Updated** SNI routing map to send `mail.reinitialized.net` to `mailProxyProtocol` upstream (local relay at 127.0.0.1:8443)
4. **Added** ACME challenge proxy in `mail.reinitialized.net` virtualHost: `/.well-known/acme-challenge/` → `http://127.0.0.1:8480` (local stream relay with PROXY protocol)
5. **Added** `stalwartOneHttps` upstream pointing to `10.255.0.3:1042` (Stalwart's HTTPS/443 listener)
6. **Added** local stream relay at `127.0.0.1:8443` → `stalwartOneHttps` with `proxy_protocol on` (HTTPS passthrough with PROXY protocol)
7. **Added** local stream relay at `127.0.0.1:8480` → `stalwartOneHttp` with `proxy_protocol on` (ACME challenge proxy with PROXY protocol)
5. **Removed** `useACMEHost` from the mail virtualHost
6. **Removed** port 8443 from firewall allowlist (loopback relay doesn't need firewall rules)

### Changes to apps1.nix
1. **Added** port mapping `"10.255.0.3:1042:443"` — exposes Stalwart's HTTPS listener (container port 443) on mesh port 1042 for TLS passthrough from rp1

### Stalwart Configuration (Database + config.toml)

Primary ACME config is stored in PostgreSQL (managed via Stalwart management API at `http://10.255.0.3:1029/api/settings`). The config.toml contains bootstrap defaults:

```toml
# ACME TLS Certificate (Let's Encrypt production, HTTP-01 challenge)
acme.letsencrypt.directory = "https://acme-v02.api.letsencrypt.org/directory"
acme.letsencrypt.challenge = "http-01"
acme.letsencrypt.contact = "admin@reinitialized.net"
acme.letsencrypt.domains.0 = "mail.reinitialized.net"
acme.letsencrypt.default = true
acme.letsencrypt.renew-before = "30d"
acme.letsencrypt.cache = "%{BASE_PATH}%/etc/acme"
```

Stalwart automatically applies the ACME cert to all listeners with `tls.implicit = true` and to STARTTLS upgrades on plaintext listeners.

### PROXY Protocol
PROXY protocol is preserved on all stream passthrough blocks (both mail protocols and HTTPS). Stalwart's `server.proxy.trusted-networks = "10.255.0.2/32"` (rp1's mesh IP specifically) expects PROXY protocol headers from rp1 to extract real client IPs for logging and security.

This has a critical implication: **ALL connections from 10.255.0.2 to Stalwart must include PROXY protocol headers**, including the ACME challenge proxy (HTTP). This is why both the HTTPS passthrough and the ACME challenge proxy use local stream relays to inject PROXY protocol.

See [stalwart-trusted-networks-proxy-protocol.md](../investigations/stalwart-trusted-networks-proxy-protocol.md).

## Trade-offs

| Aspect | Before (nginx SSL termination) | After (Stalwart native ACME) |
|--------|-------------------------------|------------------------------|
| STARTTLS (25, 143, 587) | Not supported | Fully supported |
| Cert management | rp1 via `security.acme` (DNS-01) | Stalwart built-in ACME (HTTP-01) |
| Wildcard certs | Supported (DNS-01) | Not supported (HTTP-01) |
| Challenge dependency | Technitium API token | rp1 HTTP proxy to Stalwart |
| Failure points | SNI → local SSL → PROXY → Stalwart | SNI → TCP passthrough → Stalwart |
| Cert visibility | Stalwart unaware of cert | Stalwart owns and manages cert |

## Rollout Strategy

1. **Phase 1 (Staging):** Configure Stalwart ACME with Let's Encrypt staging. Deploy rp1 changes. Verify challenge proxy works.
2. **Phase 2 (Validation):** Verify Stalwart obtains staging cert. Test HTTPS, IMAPS, SMTPS through rp1 passthrough.
3. **Phase 3 (Production):** Switch Stalwart ACME to production Let's Encrypt directory. Verify valid cert on all protocols.

## Related Documents

- [Stalwart ACME Configuration](https://stalw.art/docs/server/tls/acme/configuration)
- [Stalwart ACME Challenge Types](https://stalw.art/docs/server/tls/acme/challenges)
- [Investigation: Stalwart Trusted Networks PROXY Protocol](../investigations/stalwart-trusted-networks-proxy-protocol.md)
- [Investigation: rp1 nginx ACME Container Termination](../investigations/rp1-nginx-acme-container-termination.md)
