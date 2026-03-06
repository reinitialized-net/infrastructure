# Forgejo Runner Disk Space Exhaustion from Stale Job Containers

## Symptom

Forgejo Actions CI builds on apps2 failing with:
```
error: writing to file: No space left on device
error: filesystem error: cannot copy: No space left on device [/nix/store/...]
Error setting up pivot dir: mkdir /var/lib/docker/overlay2/.../.pivot_root...: no space left on device
```

Initial assumption was that temporary volumes from the Forgejo Runner were being written to the wrong disk (OS disk instead of data disk).

## Root Cause

**The bind mounts were working correctly** — all Docker data was confirmed on the second disk (`/dev/sdb`, 49G) via `mount` output showing `/dev/sdb on /var/lib/docker`.

The actual root cause was twofold:

1. **Stale job containers not cleaned up:** 3 failed Forgejo Actions job containers (exited with code 255) were never removed, consuming ~22.86 GB of overlay2 space on the 50 GB data disk. When these containers failed due to "no space left on device", their writable layers persisted.

2. **Insufficient disk size:** Even with cleanup, the 50 GB data disk was marginal for apps2's workload — 9 container images (~6 GB), persistent volumes (~3.4 GB), plus up to 4 concurrent Nix builds each consuming ~6-8 GB in overlay2 writable layers.

## Investigation Steps

1. **Verified bind mount configuration** — `modules/profiles/containers/default.nix` correctly binds `/var/lib/docker` → `/mnt/data/docker` on the second disk.

2. **Confirmed mounts on live system:**
   ```
   $ df -h /var/lib/docker /mnt/data
   /dev/sdb  49G  38G  12G  77%  /var/lib/docker
   /dev/sdb  49G  38G  12G  77%  /mnt/data
   ```
   Both show `/dev/sdb` — the second disk. Mounts are correct.

3. **Identified space consumers via `docker system df`:**
   ```
   Images:      5.88 GB (1.61 GB reclaimable)
   Containers: 28.86 GB (22.86 GB reclaimable - 79%!)
   Volumes:     3.39 GB (0 reclaimable)
   ```
   22.86 GB reclaimable from stopped containers.

4. **Listed containers:**
   Three stopped Forgejo Actions containers (`TASK-26`, `TASK-27`, `TASK-28`) from 37 hours prior, each consuming ~7.62 GB in overlay2 writable layers (Nix store artifacts from failed builds).

5. **Root filesystem was fine** — `/dev/sda2` at 36% (6.6 GB of 19 GB). The space issue was entirely on the second disk.

## Fix Applied

1. **Immediate cleanup:** `docker container prune -f --filter "until=1h"` — reclaimed 22.86 GB, reducing disk usage from 77% to 31%.

2. **Docker auto-prune timer** added to `modules/profiles/containers/default.nix`:
   ```nix
   virtualisation.docker.autoPrune = {
     enable = true;
     dates = "daily";
     flags = [ "--filter" "until=24h" ];
   };
   ```
   This creates a systemd timer that runs `docker system prune` daily, removing stopped containers, dangling images, and unused networks older than 24 hours. Prevents stale CI job containers from accumulating.

3. **Increased apps2 data disk** from 50 GB to 150 GB in `flake.nix` to accommodate concurrent Nix builds with headroom for growth.

## Key Insight

The Forgejo Runner normally cleans up job containers after completion. However, when a job container fails due to an infrastructure issue (like disk full), the runner may not successfully clean up the container. These orphaned containers then consume disk space, creating a cascading failure where one disk-full event prevents future builds even after the original build's workspace would have been freed.

The auto-prune timer acts as a safety net for this scenario.
