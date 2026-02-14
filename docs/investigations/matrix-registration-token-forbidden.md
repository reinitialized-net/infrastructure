# Matrix Registration Token Returns M_FORBIDDEN

## Symptom

Attempting to register an admin account on the Tuwunel Matrix homeserver using the registration token returned:

```json
{"errcode":"M_FORBIDDEN","error":"M_FORBIDDEN: Registration has been disabled."}
```

The registration command followed the documented procedure in `docs/architecture/matrix-setup.md` and included a valid `m.login.registration_token` auth type with the correct token.

## Root Cause

`CONDUWUIT_ALLOW_REGISTRATION` was set to `"false"` in the Tuwunel environment configuration (`modules/secrets/apps3.nix`). In Tuwunel (and its predecessor Conduwuit), this flag controls the **entire registration endpoint** — when set to `false`, the server rejects all registration attempts before ever inspecting the registration token.

The misconfiguration arose from a misunderstanding of how the two settings interact:

| `allow_registration` | `registration_token` set | Behavior |
|---|---|---|
| `false` | (any) | **All registration rejected** — token is never checked |
| `true` | yes | Token-gated registration — only requests with the correct token succeed |
| `true` | no | Open registration — anyone can register |

The documentation incorrectly described the intended configuration as "Registration is closed (`CONDUWUIT_ALLOW_REGISTRATION=false`)" with the expectation that the token would bypass the closure. In reality, the token mechanism only activates when registration is enabled.

## Fix

Changed `CONDUWUIT_ALLOW_REGISTRATION` from `"false"` to `"true"` in:

- `modules/secrets/apps3.nix` (live secrets)
- `modules/secrets.example/apps3.nix` (example secrets template)

This enables the registration endpoint, while `CONDUWUIT_REGISTRATION_TOKEN` ensures that only requests presenting the correct token can register. Open/unauthenticated registration is not possible with the token set.

Updated `docs/architecture/matrix-setup.md` to accurately describe the token-gated registration behavior and clarify why `allow_registration` must be `true`.

## Verification

After deploying the fix with `rebuildHost apps3`:

1. Registration with the token succeeded (returned `M_USER_IN_USE` on subsequent attempts, confirming the account was created).
2. Login with the newly created `rnetadmin` account succeeded, returning a valid access token and user ID `@rnetadmin:matrix.reinitialized.net`.
