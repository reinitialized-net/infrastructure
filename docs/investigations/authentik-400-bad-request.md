# Authentik 400 Bad Request on Nginx Reverse Proxy

## Issue Overview

When accessing `access.reinitialized.net` (Authentik SSO), the server returned a `HTTP 400 Bad Request` error immediately. 

## Investigation

Authentik is a Django-based application that enforces strict Host header checking and relies on a complete set of reverse proxy headers (`X-Forwarded-For`, `X-Forwarded-Proto`, and notably `X-Forwarded-Host`) to determine the origin of incoming requests. Without the `X-Forwarded-Host` header, Authentik's backend fails its security validation and returns a 400 Bad Request.

The `rp1.nix` Nginx reverse proxy configuration had the following overridden headers in the `extraConfig` section for `access.reinitialized.net`:

```nginx
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header Host $host;
```

### Root Cause

In Nginx, if **any** `proxy_set_header` directive is defined at the `location` level (which is where `extraConfig` is injected), Nginx will completely disable the inheritance of all `proxy_set_header` declarations from the parent `server` and `http` levels. 

By defining those three headers manually in `extraConfig`, Nginx dropped the system-wide `recommendedProxySettings` provided by NixOS, stripping out crucial headers like `X-Forwarded-Host`, `X-Forwarded-Server`, and `X-Real-IP`. As a result, Authentik received incomplete proxy properties, triggering a 400 rejection.

## Resolution

The fix addresses the root cause directly by removing the duplicate `proxy_set_header` declarations entirely from `hosts/rp1.nix`. 

NixOS natively supports forwarding proxy headers inside locations via `recommendedProxySettings = true;`, and handles bridging them directly into WebSocket locations when `proxyWebsockets = true;` is declared. By relying entirely on NixOS's module logic, Authentik now receives all required `Host` and `X-Forwarded-*` headers intact, resolving the 400 error. 

**Commit/Change details:**
- Removed `proxy_set_header` overrides in `hosts/rp1.nix` -> `access.reinitialized.net` `extraConfig`.
