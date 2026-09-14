"""Experimental recording-worker liveness; independent of retained clip activity."""

import math
from pathlib import Path
import time


HEARTBEAT = Path('/tmp/cache/gecko-recording-heartbeat')
DETECTOR_HEARTBEAT = Path('/tmp/cache/gecko-detector-heartbeat')


def heartbeat(path=HEARTBEAT):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(str(time.monotonic()))
    temporary.replace(path)


def check_heartbeat(path=HEARTBEAT, now=None, max_age=120, worker_name='recording'):
    try:
        timestamp = float(path.read_text())
    except (OSError, ValueError):
        raise RuntimeError(f'Gecko {worker_name} worker has no valid heartbeat') from None
    age = (time.monotonic() if now is None else now) - timestamp
    if not math.isfinite(age) or not 0 <= age <= max_age:
        raise RuntimeError(f'Gecko {worker_name} worker heartbeat is stale')
