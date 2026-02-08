# Docker Volume Migration Script - Permission Denied Errors

**Date:** 2026-02-07  
**Status:** Resolved  
**Affected Component:** `modules/profiles/containers/tools/migrate-volumes.sh`

## Problem Description

The `migrate-volumes.sh` script was failing with permission denied errors when attempting to run Docker operations on remote hosts. The script would fail during the import phase with the error:

```
sudo: /nix/store/2g9xf9m6wqavsj9g30z43v1091pcpqs7-sudo-1.9.17p2/bin/sudo must be owned by uid 0 and have the setuid bit set
```

## Root Cause Analysis

### Primary Issue: Nix Store Sudo Without Setuid Bit

The script was using the Nix store path for sudo (`@sudo@/bin/sudo`) which resolves to `/nix/store/.../sudo`. This binary does **not** have the setuid bit set, which is required for sudo to properly elevate privileges.

In NixOS, setuid programs (like sudo, ping, etc.) are handled specially through a wrapper system located at `/run/wrappers/bin/`. These wrappers have the setuid bit properly set and are owned by root.

**Investigation Steps:**
1. Created test volume with sample data
2. Attempted export operation - succeeded locally
3. Attempted transfer to remote host - succeeded
4. Attempted import on remote host - **failed** with sudo permission error
5. Inspected sudo binary locations:
   - Nix store: `/nix/store/.../bin/sudo` (no setuid bit)
   - System wrapper: `/run/wrappers/bin/sudo` (proper setuid bit)
   ```bash
   $ ls -la /run/wrappers/bin/sudo
   -r-s--x--x 1 root root 70712 Feb  7 14:16 /run/wrappers/bin/sudo
   ```

### Secondary Issue: Docker Socket Permissions

On some hosts, the user does not have direct access to the Docker socket (`/var/run/docker.sock`), requiring sudo for all Docker operations. The script's `check_sudo()` function properly detects this, but the incorrect sudo path prevented it from working.

## Solution

Changed the `check_sudo()` function to use the NixOS system sudo wrapper at `/run/wrappers/bin/sudo` instead of the Nix store path:

```bash
# Before (incorrect):
USE_SUDO="@sudo@/bin/sudo"

# After (correct):
USE_SUDO="/run/wrappers/bin/sudo"
```

This ensures that:
1. The sudo binary has the proper setuid bit set
2. Privilege elevation works correctly for Docker operations
3. The script functions properly on all hosts regardless of Docker socket permissions

## Implementation

**File Modified:** [modules/profiles/containers/tools/migrate-volumes.sh](../modules/profiles/containers/tools/migrate-volumes.sh)

**Change:**
```diff
 check_sudo() {
     if [ -z "$USE_SUDO" ]; then
         # Check if we can access docker without sudo
         if @docker@/bin/docker ps &>/dev/null; then
             USE_SUDO=""
             print_info "Docker accessible without sudo"
         else
-            USE_SUDO="@sudo@/bin/sudo"
+            # Use system sudo wrapper which has setuid bit set on NixOS
+            USE_SUDO="/run/wrappers/bin/sudo"
             print_info "Using sudo for Docker operations"
         fi
     fi
 }
```

## Validation

The fix was validated through comprehensive end-to-end testing:

### Test 1: Local Export
```bash
$ docker volume create test-migrate-vol
$ migrate-volumes export -v test-migrate-vol -n
[SUCCESS] Volume exported successfully
```

### Test 2: Transfer to Remote Host
```bash
$ migrate-volumes transfer -v test-migrate-vol -r rnetadmin@10.1.11.2 -V imported-test-vol -n
[SUCCESS] Transfer completed
```

### Test 3: Import on Remote Host (Previously Failed)
```bash
$ ssh rnetadmin@10.1.11.2 "migrate-volumes import -v imported-test-vol -f /tmp/volume-migrations/test-migrate-vol.tar.gz -n"
[INFO] Using sudo for Docker operations
[SUCCESS] Checksum verified
[SUCCESS] Volume imported successfully
```

### Test 4: Data Integrity Verification
```bash
$ ssh rnetadmin@10.1.11.2 "sudo docker run --rm -v imported-test-vol:/data alpine find /data -type f -exec cat {} \;"
Critical production data
setting=value
```

All test cases passed successfully on all hosts:
- devenv (10.1.200.1) - direct Docker access
- rp1 (10.1.11.1) - requires sudo
- apps1 (10.1.11.2) - requires sudo
- apps2 (10.1.11.3) - requires sudo
- db1 (10.1.11.11) - requires sudo

## Lessons Learned

1. **NixOS Setuid Programs**: In NixOS, always use `/run/wrappers/bin/` for setuid programs (sudo, ping, mount, etc.), never the Nix store paths directly.

2. **Substitution in Scripts**: When using Nix's `makeToolScript` pattern with package substitutions (`@package@`), be careful with security-sensitive binaries that require special permissions.

3. **Testing Across Hosts**: Permission issues may not manifest on all systems - test on hosts with different permission configurations (Docker socket access, sudo requirements, etc.).

4. **Root Cause Investigation**: The initial symptom (permission denied) required tracing through the full execution path to identify the actual cause (incorrect sudo path) rather than applying surface-level workarounds.

## Related Documentation

- [NixOS Manual - Setuid Wrappers](https://nixos.org/manual/nixos/stable/#sec-setuid-wrappers)
- [Container Tools Documentation](../modules/containers.md)
- [migrate-volumes.sh Script](../bash-script-tools.md#migrate-volumes)

## Deployment

The fix was deployed to all hosts on 2026-02-07:
```bash
rebuildHost devenv  # Local rebuild
rebuildHost apps1
rebuildHost apps2
rebuildHost rp1
rebuildHost db1
```

All hosts now have the corrected script available in their system path.
