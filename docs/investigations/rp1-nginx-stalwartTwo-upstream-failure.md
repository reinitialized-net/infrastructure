# Investigation: rp1 Nginx Failure — Undefined `stalwartTwoHttp` Upstream

**Date:** 2026-02-07  
**Affected host:** rp1  
**Symptom:** All ports on rp1 reported as closed by external port-check tools (yougetsignal.com)

## Root Cause

The Angie (nginx) process inside the `nginx` NixOS container on rp1 failed to start due to a configuration error referencing an undefined upstream.

The `streamConfig` in `hosts/rp1.nix` contained a server block for future `stalwartTwo` (mail2) SSL termination:

```nginx
server {
    listen 127.0.0.1:8444 ssl;
    ssl_certificate /var/lib/acme/mail2.reinitialized.net/fullchain.pem;
    ssl_certificate_key /var/lib/acme/mail2.reinitialized.net/key.pem;
    proxy_pass stalwartTwoHttp;
    proxy_protocol on;
}
```

This block referenced `stalwartTwoHttp` as an upstream, but no corresponding `upstream stalwartTwoHttp { ... }` definition existed — only a placeholder comment `# Stalwart Mail (stalwartTwo on apps2 - future)`. Because Angie validates all upstream references at config-test time, the entire configuration was rejected:

```
angie: [emerg] no port in upstream "stalwartTwoHttp" in nginx.conf:258
angie: configuration file test failed
```

Since **all** rp1 reverse proxy services (DNS, HTTPS, mail, etc.) are served through this single Angie instance inside the container, one invalid upstream reference caused a total service outage for every port on rp1.

## Steps to Identify

1. Checked firewall rules on rp1 via `nft list ruleset` — rules were correct and ports were allowed.
2. Checked listening ports via `ss -tlnp` — only `sshd` and `systemd-resolved` were listening; nginx was absent.
3. Checked container status via `machinectl list` — container was running but nginx inside had failed.
4. Checked `systemctl status nginx.service` inside the container — showed `failed (Result: exit-code)` with 5 rapid restart attempts.
5. Read `journalctl -u nginx.service` inside the container — revealed the `[emerg] no port in upstream "stalwartTwoHttp"` error repeated on every start attempt.

## Fix Applied

Removed the two elements that referenced the non-existent `stalwartTwo` service from `hosts/rp1.nix`:

1. **Removed the `stalwartTwoHttp` server block** — the `127.0.0.1:8444` SSL termination listener that used `proxy_pass stalwartTwoHttp`.
2. **Removed the placeholder comment** — `# Stalwart Mail (stalwartTwo on apps2 - future)` which gave the false impression the upstream was harmlessly commented out.

After deploying with `rebuildHost rp1`, Angie started successfully and all ports became operational.

## Lessons Learned

- Nginx/Angie validates the **entire** configuration at startup. A single invalid upstream reference in the `stream` block prevents all services from starting, including unrelated HTTP virtual hosts.
- Future/placeholder service references should never be included in active configuration blocks — they should be fully commented out or gated behind conditionals.
- When adding upstream references for planned services, either define a stub upstream with a placeholder server or keep the entire server block commented out until the service is ready.
