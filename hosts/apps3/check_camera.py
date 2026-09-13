"""Health check for apps3's camera, run inside the pinned Frigate container.

The stock check only tests API availability. Require fresh capture statistics
and usable recording-stream keyframes as well; do not restart the camera here.
"""

import json
from pathlib import Path
import subprocess
import sys
import time
from urllib.request import urlopen

from frigate.util.media import FFPROBE_PATH


def api(path):
    with urlopen("http://127.0.0.1:5000/api/" + path, timeout=3) as response:
        return json.load(response)


def check():
    if Path("/dev/shm/.frigate-is-stopping").exists():
        return

    camera = api("config")["cameras"]["camera_13_37"]
    if not camera["enabled"]:
        return
    stats = api("stats")
    if time.time() - stats["service"]["last_updated"] > 90:
        raise RuntimeError("Camera statistics are stale")
    # process_fps can retain its last value during an outage; use camera_fps.
    if stats["cameras"]["camera_13_37"]["camera_fps"] <= 0:
        raise RuntimeError("Camera capture is receiving no frames")

    if camera["record"]["enabled"]:
        # Probe the shared local restream, never a second camera connection.
        # No retained-file freshness check: motion-only recording can be idle.
        probe = subprocess.run(
            [
                FFPROBE_PATH, "-v", "error", "-rtsp_transport", "tcp",
                "-timeout", "5000000", "-read_intervals", "%+8",
                "-select_streams", "v:0", "-show_packets",
                "-show_entries", "packet=flags", "-of", "json",
                "rtsp://127.0.0.1:8554/camera_13_37",
            ],
            capture_output=True, text=True, timeout=20,
        )
        if probe.returncode != 0:
            raise RuntimeError("Recording stream probe failed")
        packets = json.loads(probe.stdout).get("packets", [])
        if not any("K" in packet.get("flags", "") for packet in packets):
            raise RuntimeError("Recording stream has no keyframes in 8 seconds")


if __name__ == "__main__":
    try:
        check()
    except RuntimeError as error:
        print(str(error))
        sys.exit(1)
    except Exception as error:
        # Never put response bodies, camera URLs, or credentials in health logs.
        print("Camera health check failed: " + type(error).__name__)
        sys.exit(1)
    print("Camera capture and recording stream are healthy")
