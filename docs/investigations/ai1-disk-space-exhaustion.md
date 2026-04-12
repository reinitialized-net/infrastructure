# Disk Space Exhaustion on ai1 during Rebuild

## Root Cause
The root partition (`/dev/sdb2`) on host `ai1` was 100% full, causing `nix-copy-closure` to fail during `rebuildHost ai1`. 

Investigation revealed that `/var/lib/llamacpp/.cache` was consuming approximately 6.9GB of space, primarily due to downloaded HuggingFace models (specifically `unsloth/gemma-4-26B-A4B-it-GGUF`). Since the root partition is relatively small (19GB), this cache quickly exhausted the available space.

## Identification Steps
1. Ran `df -h` on `ai1` to confirm the root partition was at 100% usage.
2. Used `du -sh` recursively starting from `/` to identify the largest directories.
3. Found that `/var/lib` was the primary consumer of space.
4. Drilled down into `/var/lib/llamacpp/.cache` and identified the large model files.

## Resolution
1. Manually cleared the cache by running `sudo rm -rf /var/lib/llamacpp/.cache` on `ai1`.
2. Verified that space was freed (`df -h /` showed ~6.9GB available).
3. Successfully ran `rebuildHost ai1` to confirm the system could be updated.

## Long-term Fix
The rebuild output indicated that `var-lib-llamacpp.mount` was started. This suggests that a mount point has been configured to move `/var/lib/llamacpp` to the larger `/mnt/data` partition, which will prevent this issue from recurring.
