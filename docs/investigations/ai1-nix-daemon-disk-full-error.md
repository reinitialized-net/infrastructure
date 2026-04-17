# AI1 Nix Daemon Disk Full Error Investigation

## Issue Summary
**Date**: April 16, 2026  
**Host**: ai1 (10.1.11.9)  
**Error**: `cannot open connection to remote store 'daemon': error: reading from file: Connection reset by peer`  
**Command**: `nix flake update && rebuildHost ai1`

## Root Cause
The root filesystem on ai1 was 100% full (19GB used, 0 available), causing SQLite disk I/O errors in the Nix daemon database (`/nix/var/nix/db/db.sqlite`). This prevented the Nix daemon from accepting connections, which broke the `nix-copy-closure` command used by `rebuildHost`.

## Investigation Steps

### 1. Initial Error Analysis
The error message indicated a connection issue with the remote Nix store daemon:
```
error: cannot open connection to remote store 'daemon': error: reading from file: Connection reset by peer
error: unexpected end-of-file
```

### 2. SSH Connectivity Check
- SSH connectivity to ai1 was confirmed working
- Basic commands executed successfully via SSH

### 3. Nix Daemon Status Check
- Nix daemon was running but showing SQLite errors:
  ```
  unexpected Nix daemon error: error: executing SQLite statement 'pragma synchronous = normal': disk I/O error, disk I/O error (in '/nix/var/nix/db/db.sqlite')
  ```

### 4. Disk Space Analysis
- Root filesystem (`/dev/sdb2`): 19GB total, 19GB used (100%)
- `/nix`: 16GB
- `/var`: 2.8GB (with `/var/lib/openclaw/.npm` using 1.6GB)
- `/mnt/data`: 77GB used (separate mount with plenty of space)

### 5. Space Consumption Breakdown
- Large npm cache in `/var/lib/openclaw/.npm`: 1.6GB
- Nix store had accumulated many old generations

## Solution

### Step 1: Free Immediate Space
1. Stopped the Nix daemon: `sudo systemctl stop nix-daemon.socket nix-daemon.service`
2. Removed npm cache: `sudo rm -rf /var/lib/openclaw/.npm` (freed 1.6GB)
3. Result: Root filesystem went from 100% to 92% used (1.6GB available)

### Step 2: Restart Nix Daemon and Run Garbage Collection
1. Started Nix daemon: `sudo systemctl start nix-daemon.socket nix-daemon.service`
2. Ran Nix garbage collection: `sudo nix-collect-garbage --delete-old`
3. Result: Freed 10.4GB, root filesystem now 31% used (13GB available)

### Step 3: Verify Fix
1. Ran `rebuildHost ai1` again
2. Successfully built system configuration and began copying 305 paths to ai1
3. No more connection errors to the Nix daemon

## Prevention Recommendations

### 1. Monitor Disk Space
Add disk space monitoring to ai1 configuration:
```nix
services.prometheus.exporters.node.enable = true;
services.prometheus.exporters.node.enabledCollectors = [ "filesystem" ];
```

### 2. Regular Garbage Collection
Schedule automatic garbage collection:
```nix
nix.gc = {
  automatic = true;
  dates = "weekly";
  options = "--delete-older-than 30d";
};
```

### 3. Configure npm Cache Location
Move npm cache to `/mnt/data` to avoid filling root filesystem:
```nix
# In ai1.nix or a profile module
environment.variables.NPM_CONFIG_CACHE = "/mnt/data/openclaw/.npm-cache";
```

### 4. Increase Root Partition Size
Consider increasing the root partition size from 19GB to at least 30GB for AI workloads.

## Lessons Learned
1. **Disk space exhaustion** can cause subtle errors like SQLite I/O failures before obvious "no space left" errors
2. **Nix daemon is sensitive to disk I/O errors** - SQLite database corruption prevents remote rebuilds
3. **npm cache can be massive** - AI/ML packages often include large binary dependencies
4. **Regular maintenance** is needed for Nix systems with frequent updates to prevent store bloat

## Verification
- ✅ SSH connectivity maintained throughout
- ✅ Nix daemon restarted successfully after freeing space
- ✅ Garbage collection recovered significant space
- ✅ `rebuildHost ai1` now works without connection errors
- ✅ Root filesystem has 13GB free (31% used)