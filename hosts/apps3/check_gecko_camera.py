"""Keep capture/keyframe checks and require progress from the recording worker."""

from pathlib import Path
import sys

from check_camera import api, check
from frigate.gecko_recording_health import DETECTOR_HEARTBEAT, check_heartbeat


if __name__ == '__main__':
    try:
        check()
        if not Path('/dev/shm/.frigate-is-stopping').exists():
            camera = api('config')['cameras']['camera_13_37']
            if camera['enabled'] and camera['record']['enabled']:
                check_heartbeat()
            if camera['enabled'] and camera['detect']['enabled']:
                check_heartbeat(DETECTOR_HEARTBEAT, max_age=30, worker_name='detector')
    except RuntimeError as error:
        print(str(error))
        sys.exit(1)
    except Exception as error:
        print('Gecko camera health check failed: ' + type(error).__name__)
        sys.exit(1)
    print('Camera capture, detector, recording stream and recording worker are healthy')
