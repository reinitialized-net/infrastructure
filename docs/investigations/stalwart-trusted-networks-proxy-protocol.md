# Investigation: Stalwart "Invalid Proxy Header" with Trusted Networks

**Date:** 2026-02-08  
**Host:** rp1  
**Service:** Nginx stream SSL termination for mail.reinitialized.net  
**Symptom:** "invalid proxy header" error when accessing mail.reinitialized.net via HTTPS

## Summary

After configuring `trusted-networks` in Stalwart Mail Server, the web UI became inaccessible via the rp1 reverse proxy, returning "invalid proxy header" errors. This required re-enabling PROXY protocol on the nginx stream SSL termination block, reversing a previous fix.

## Root Cause

Stalwart Mail Server's behavior with PROXY protocol depends on its `trusted-networks` configuration:

### Without trusted-networks (Previous State)
- Stalwart HTTP listener does NOT expect PROXY protocol headers
- If nginx sends PROXY protocol headers, Stalwart returns 400 Bad Request
- **Solution:** Do NOT use `proxy_protocol on` in nginx

### With trusted-networks (Current State)
- Stalwart HTTP listener EXPECTS PROXY protocol headers from trusted IP ranges
- If nginx does NOT send PROXY protocol headers from a trusted source, Stalwart returns "invalid proxy header"
- **Solution:** MUST use `proxy_protocol on` in nginx

The configuration change in Stalwart (adding trusted-networks) fundamentally changed the expected protocol, requiring a corresponding change in the nginx reverse proxy configuration.

## Background

The nginx reverse proxy on rp1 handles HTTPS for mail.reinitialized.net using stream SSL termination:

1. Public HTTPS (443) → rp1 SNI routing based on hostname
2. rp1 stream server (127.0.0.1:8443) terminates SSL
3. Forwards plain HTTP to stalwartOne (10.255.0.3:1029 → container port 8080)

Previously, the stream block did NOT include `proxy_protocol on` because Stalwart's HTTP listener was not configured with trusted-networks. This was documented in [rp1-nginx-acme-container-termination.md](rp1-nginx-acme-container-termination.md) where `proxy_protocol on` was intentionally removed to fix 400 errors.

## Steps to Identify Root Cause

1. User reported "invalid proxy header" error when accessing mail.reinitialized.net
2. User confirmed they had configured trusted-networks in Stalwart
3. Reviewed previous investigation ([rp1-nginx-acme-container-termination.md](rp1-nginx-acme-container-termination.md)) which documented removing `proxy_protocol on`
4. Understood that trusted-networks configuration changes Stalwart's expectations:
   - Connections from trusted IPs MUST include PROXY protocol headers
   - Connections from trusted IPs WITHOUT PROXY protocol headers are rejected
5. Verified current nginx configuration lacked `proxy_protocol on` in the stream SSL termination block

## Changes Made

### hosts/rp1.nix

**Re-enabled PROXY protocol on stream SSL termination:**
```nix
server {
  listen 127.0.0.1:8443 ssl;
  ssl_certificate /var/lib/acme/mail.reinitialized.net/fullchain.pem;
  ssl_certificate_key /var/lib/acme/mail.reinitialized.net/key.pem;
  proxy_pass stalwartOneHttp;
  proxy_protocol on;  # REQUIRED when Stalwart has trusted-networks configured
}
```

**Updated comments to reflect the trusted-networks requirement:**
- Explained that PROXY protocol is required because of trusted-networks configuration
- Noted that this preserves client IP addresses for Stalwart's access logs and security features

## Verification

After deploying the changes:
```bash
# Access the web UI through the reverse proxy
curl -sk https://mail.reinitialized.net
```

Should return HTTP 200 with the Stalwart login page, not "invalid proxy header" error.

## Architecture Notes

### PROXY Protocol Configuration Matrix

| Listener Type | Stalwart Config | Nginx Config | Status |
|---------------|----------------|--------------|--------|
| HTTP Web UI (port 8080) | No trusted-networks | No `proxy_protocol on` | Previous |
| HTTP Web UI (port 8080) | Has trusted-networks | `proxy_protocol on` | **Current** |
| Mail protocols (SMTP, IMAP, etc.) | Always configured for PROXY | `proxy_protocol on` | Always |

### Trust Network Configuration

When Stalwart is configured with trusted-networks (typically `10.1.12.0/24` for rp1's subnet), it:
1. Expects PROXY protocol v1 or v2 headers from connections originating from those IPs
2. Extracts the real client IP from the PROXY header for logging and access control
3. Rejects connections from trusted IPs that don't include valid PROXY headers

This is intentional behavior - it prevents IP spoofing by ensuring proxies properly identify themselves and the real client.

## Lessons Learned

1. **Stalwart's PROXY protocol behavior is context-dependent**: Without trusted-networks, PROXY protocol is rejected. With trusted-networks, it's required for connections from those networks.

2. **Application configuration changes require infrastructure updates**: When modifying application-level settings like trusted-networks, corresponding changes may be needed in the reverse proxy layer.

3. **Previous fixes may need reverting when requirements change**: The removal of `proxy_protocol on` was correct at the time, but became incorrect when Stalwart's configuration changed. This is not a regression - it's an intentional adaptation to new requirements.

4. **Documentation prevents confusion**: Having the previous investigation documented made it easy to understand why `proxy_protocol on` was removed and why it now needs to be re-enabled.

## Related Investigations

- [rp1-nginx-acme-container-termination.md](rp1-nginx-acme-container-termination.md) - Original removal of PROXY protocol from HTTP listener (now superseded by trusted-networks configuration)
