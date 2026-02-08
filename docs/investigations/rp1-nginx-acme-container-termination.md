# rp1 Nginx Container Termination and Mail Web UI Inaccessible

**Date:** 2026-02-07  
**Status:** Fixed

## Symptoms

1. The nginx NixOS container on rp1 was being forcefully terminated during startup or ACME certificate renewal cycles. The container would enter a restart loop, with the host killing it after `TimeoutStartSec` elapsed.
2. After resolving the container termination, `https://mail.reinitialized.net` returned **HTTP 400 Bad Request** instead of the Stalwart web UI.

## Root Cause

Three distinct issues combined to cause the problems:

### 1. Stream SSL Certificate Dependency Race (Container Termination)

The nginx stream configuration includes an SSL-terminating server block:

```nginx
server {
    listen 127.0.0.1:8443 ssl;
    ssl_certificate /var/lib/acme/mail.reinitialized.net/fullchain.pem;
    ssl_certificate_key /var/lib/acme/mail.reinitialized.net/key.pem;
    proxy_pass stalwartOneHttp;
}
```

This block references ACME certificate files directly. The NixOS ACME module generates self-signed placeholder certificates via `acme-mail.reinitialized.net.service` before the real ACME order runs, **but** the nginx module only auto-creates systemd dependencies for certs used via `enableACME`/`useACMEHost` on **virtualHosts**. Stream configs are opaque strings — nginx has no knowledge that they reference cert files.

Without an explicit dependency, nginx could attempt to start **before** `acme-mail.reinitialized.net.service` had generated even the self-signed placeholder. Nginx would fail to start (missing cert files), the container's boot transaction would stall, and the host would kill the container after `TimeoutStartSec`.

### 2. PROXY Protocol on HTTP Backend (400 Bad Request)

The stream SSL termination block had `proxy_protocol on`, causing nginx to prepend a PROXY protocol header when forwarding to `stalwartOneHttp` (10.255.0.3:1029 → Stalwart's internal port 8080). Stalwart's HTTP web UI listener does not expect PROXY protocol — it interpreted the PROXY header as a malformed HTTP request and returned 400.

PROXY protocol is correctly used on the mail protocol ports (SMTP/25, IMAP/143, etc.) because Stalwart's mail listeners are configured to accept it. But the HTTP web UI is a different listener class.

**Diagnostic steps:**
- `curl -sk http://10.255.0.3:1029` → HTTP 200 (direct access without PROXY protocol works)
- `curl -sk https://127.0.0.1:8443` → HTTP 400 (through stream SSL termination with PROXY protocol fails)

### 3. Bogus acmeDomains Entry

The `acmeDomains` list included `"mail2.reinitialized.net"`, which had no corresponding `security.acme.certs` entry. While functionally harmless, it was misleading.

## Steps to Identify Root Cause

1. Reviewed the rp1 container configuration and identified the ephemeral NixOS container with bind-mounted `/var/lib/acme`
2. Traced the stream SSL block's direct reference to `/var/lib/acme/mail.reinitialized.net/` cert files
3. Researched the NixOS ACME module (nixos-25.11) to understand how self-signed placeholder certificates are generated and how nginx dependencies are wired
4. Discovered that the nginx module only creates systemd ordering dependencies for certs referenced by virtualHosts (`enableACME`/`useACMEHost`), not for certs referenced in stream config strings
5. Identified that without `wants`/`after` on `acme-mail.reinitialized.net.service`, nginx could start before the self-signed cert was provisioned
6. Found the stale `mail2.reinitialized.net` entry in the override list with no matching cert definition

## Changes Made

### hosts/rp1.nix

1. **Added explicit nginx → ACME service dependency:**
   ```nix
   systemd.services.nginx = {
     wants = [ "acme-mail.reinitialized.net.service" ];
     after = [ "acme-mail.reinitialized.net.service" ];
   };
   ```
   This ensures the self-signed placeholder cert is generated before nginx starts, so the stream SSL block always has valid cert files.

2. **Removed `proxy_protocol on` from the stream SSL termination block:**
   ```nginx
   server {
       listen 127.0.0.1:8443 ssl;
       ssl_certificate /var/lib/acme/mail.reinitialized.net/fullchain.pem;
       ssl_certificate_key /var/lib/acme/mail.reinitialized.net/key.pem;
       proxy_pass stalwartOneHttp;
       # No proxy_protocol — Stalwart's HTTP listener doesn't expect it
   }
   ```
   PROXY protocol remains enabled on all mail protocol stream listeners (SMTP, IMAP, etc.) where Stalwart expects it.

3. **Added `reloadServices` to the mail cert:**
   ```nix
   security.acme.certs."mail.reinitialized.net" = {
     reloadServices = [ "nginx.service" ];
   };
   ```
   This ensures nginx reloads to pick up the real ACME certificate when it arrives, replacing the self-signed placeholder.

4. **Removed `"mail2.reinitialized.net"` from `acmeDomains`:**
   No cert definition exists for this domain. The override was targeting a nonexistent service.

## Related

- [Port Mapping Scheme Migration](port-mapping-scheme-migration.md) — Concurrent fix for mismatched stalwart upstream ports in rp1
- [Mesh Network Port Reference](../mesh-network-ports.md) — Updated port allocations
