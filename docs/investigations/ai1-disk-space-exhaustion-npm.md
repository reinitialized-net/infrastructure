# Disk Space Exhaustion on ai1 (sdb2)

## Root Cause
The root filesystem (`/dev/sdb2`) on `ai1` reached 82% usage, which was preventing system updates. The investigation revealed that the primary consumers of space were `.npm` caches in multiple user directories:
- `/home/rnetadmin/.npm`: ~1.7 GB
- `/var/lib/openclaw/.npm`: ~1.9 GB

Additionally, `/var/lib/private/open-webui/transformers_home` was consuming ~888 MB due to a sentence-transformers model.

## Identification Steps
1. Verified disk usage using `df -h` via SSH.
2. Used `du -sh` on top-level directories to narrow down the space consumers.
3. Identified large `.npm` directories in `/home/rnetadmin` and `/var/lib/openclaw`.
4. Identified a large model directory in `/var/lib/private/open-webui`.

## Fix
The `.npm` caches were removed to reclaim space:
- `sudo rm -rf /home/rnetadmin/.npm`
- `sudo rm -rf /var/lib/openclaw/.npm`

This reclaimed approximately 3.6 GB of space, reducing the disk usage from 82% to 73%.

## Results
- **Before:** 82% used (3.5 GB available)
- **After:** 73% used (5.2 GB available)
