# Authentik OIDC Auto-Registration

## Overview

All Authentik-managed services are configured to automatically create user accounts on first OIDC login (just-in-time provisioning). This eliminates the need for manual account creation in each service — users authenticate once via Authentik and accounts are provisioned automatically.

## Services and Auto-Registration Status

| Service | Host | Auth Method | Auto-Registration | Key Setting |
|---------|------|-------------|-------------------|-------------|
| ownCloud Infinite Scale | apps3 | OIDC (Authentik) | Enabled | `PROXY_AUTOPROVISION_ACCOUNTS=true` |
| Immich | apps3 | OIDC (Authentik) | Enabled | `IMMICH_OIDC_AUTO_REGISTER=true` |
| Forgejo | apps1 | OAuth2/OIDC (Authentik) | Enabled | `FORGEJO__oauth2_client__ENABLE_AUTO_REGISTRATION=true` |

## How It Works

### Authentication Flow

```
User → Service Login Page → "Login with Authentik"
  → Redirect to Authentik (access.reinitialized.net)
  → User authenticates (username/password, MFA, etc.)
  → Authentik issues OIDC tokens (id_token, access_token)
  → Redirect back to service with authorization code
  → Service exchanges code for tokens
  → Service checks: does a local account match this OIDC identity?
    → YES: Log in to existing account (optionally link if email matches)
    → NO: Auto-create new local account from OIDC claims
  → User is logged in
```

### OIDC Claims Used

All services map the following standard OIDC claims for account creation:

| Claim | Purpose | Example Value |
|-------|---------|---------------|
| `preferred_username` | Username/login | `jdoe` |
| `email` | Email address | `jdoe@reinitialized.net` |
| `name` | Display name | `John Doe` |
| `groups` | Role/group assignment | `["Super Administrators", "OwnCloud - Users"]` |

## Service-Specific Configuration

### ownCloud Infinite Scale (OCIS)

**Secrets:** `modules/secrets/apps3.nix` → `secrets.ocis.keys`

OCIS uses its built-in proxy for OIDC handling. Auto-provisioning is configured via proxy environment variables:

```nix
# Auto-provision user accounts on first OIDC login
PROXY_AUTOPROVISION_ACCOUNTS = "true";
PROXY_AUTOPROVISION_CLAIM_USERNAME = "preferred_username";
PROXY_AUTOPROVISION_CLAIM_EMAIL = "email";
PROXY_AUTOPROVISION_CLAIM_DISPLAYNAME = "name";

# Role assignment via OIDC groups claim
PROXY_ROLE_ASSIGNMENT_DRIVER = "oidc";
PROXY_ROLE_ASSIGNMENT_OIDC_CLAIM = "groups";
```

Role mapping is defined in `hosts/apps3.nix` via the `proxy.yaml` config file:
- `Super Administrators` / `OwnCloud - Administrators` → `admin` role
- `Super User` / `Super Users` / `OwnCloud - Users` → `user` role

### Immich

**Secrets:** `modules/secrets/apps3.nix` → `secrets.immich.keys`

Immich has native OIDC support via environment variables:

```nix
IMMICH_OIDC_ENABLED = "true";
IMMICH_OIDC_ISSUER_URL = "https://access.reinitialized.net/application/o/immich/";
IMMICH_OIDC_CLIENT_ID = "<client_id>";
IMMICH_OIDC_CLIENT_SECRET = "<client_secret>";
IMMICH_OIDC_SCOPE = "openid profile email";
IMMICH_OIDC_STORAGE_LABEL_CLAIM = "preferred_username";
IMMICH_OIDC_BUTTON_TEXT = "Login with Authentik";
IMMICH_OIDC_AUTO_REGISTER = "true";
```

### Forgejo

**Secrets:** `modules/secrets/apps1.nix` → `secrets.forgejo.keys`

Forgejo uses Gitea-compatible `FORGEJO__` prefixed environment variables to control OAuth2 client behavior:

```nix
# Auto-create user account on first OAuth2/OIDC login
FORGEJO__oauth2_client__ENABLE_AUTO_REGISTRATION = "true";
# Auto-link OIDC identity to existing local account by email match
FORGEJO__oauth2_client__ACCOUNT_LINKING = "auto";
```

**Important:** The OAuth2 provider (Authentik) must be registered in Forgejo's admin panel (`Site Administration → Authentication Sources → Add Authentication Source`). The environment variables above only control the auto-registration *behavior* — they do not register the provider itself. See [Registering the OAuth2 Provider in Forgejo](#registering-the-oauth2-provider-in-forgejo) below.

## Authentik Application Configuration

Each service requires a corresponding Application and OAuth2/OIDC Provider in Authentik:

| Application Slug | Redirect URI | Client Type |
|-----------------|--------------|-------------|
| `ocis` | `https://cloud.reinitialized.net/` | Confidential |
| `immich` | `https://photos.reinitialized.me/auth/login` | Confidential |
| `forgejo` | `https://git.ds.reinitialized.net/user/oauth2/authentik/callback` | Confidential |

**Issuer URLs** (used by services to discover Authentik's OIDC endpoints):
```
https://access.reinitialized.net/application/o/<app-slug>/
```

**Well-Known Configuration** (auto-discovery):
```
https://access.reinitialized.net/application/o/<app-slug>/.well-known/openid-configuration
```

## Registering the OAuth2 Provider in Forgejo

Unlike OCIS and Immich, Forgejo does not support registering OAuth2 providers via environment variables. The provider must be registered through the Forgejo admin panel or API:

### Via Admin Panel

1. Navigate to `Site Administration → Authentication Sources → Add Authentication Source`
2. Select **OAuth2** as the source type
3. Configure:
   - **Name:** `Authentik`
   - **Provider:** `OpenID Connect`
   - **Client ID:** (from Authentik provider)
   - **Client Secret:** (from Authentik provider)
   - **Icon URL:** `https://access.reinitialized.net/static/dist/assets/icons/icon.svg`
4. Under **OpenID Connect Auto Discovery URL:**
   ```
   https://access.reinitialized.net/application/o/forgejo/.well-known/openid-configuration
   ```
5. Enable **Skip local 2FA** (optional, if Authentik handles MFA)
6. Save

### Via Forgejo API

```bash
# Using forgejo CLI inside the container
docker exec forgejo forgejo admin auth add-oauth \
  --name authentik \
  --provider openidConnect \
  --key "<CLIENT_ID>" \
  --secret "<CLIENT_SECRET>" \
  --auto-discover-url "https://access.reinitialized.net/application/o/forgejo/.well-known/openid-configuration" \
  --skip-local-2fa
```

## Troubleshooting

### User Not Auto-Created

**Symptom:** User gets an error after OIDC login instead of being auto-created.

**Check:**
1. Verify the auto-registration setting is enabled in the service's secrets
2. Check service logs for specific error messages
3. For Forgejo: verify the OAuth2 provider is registered in the admin panel
4. For OCIS: verify `PROXY_AUTOPROVISION_ACCOUNTS` is `"true"` (not `"false"`)

### Account Linking Failures

**Symptom:** User with existing local account gets a duplicate account or error.

**Check:**
1. For Forgejo: `ACCOUNT_LINKING` should be `"auto"` to match by email
2. For OCIS: `PROXY_USER_OIDC_CLAIM` should match the claim used for username
3. Ensure the user's email in Authentik matches the email in the local service

### OIDC Discovery Failures

**Symptom:** Service cannot reach Authentik's well-known endpoint.

**Check:**
1. Verify DNS resolution for `access.reinitialized.net` from the service container
2. Verify rp1 reverse proxy is correctly routing to Authentik
3. Check that the issuer URL includes the trailing slash: `https://access.reinitialized.net/application/o/<slug>/`

## See Also

- [Mesh Network Ports](../mesh-network-ports.md) - Port allocations for Authentik (apps1:1043) and OCIS (apps3:1028)
- [Secrets Module](../modules/secrets.md) - Secrets management for OIDC credentials
- [Containers Profile](../modules/containers.md) - Docker container configuration
