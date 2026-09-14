"""Experimental frame-bounded gecko clips; intermediates stay in volatile cache."""

import asyncio
from fractions import Fraction
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

from frigate.util.media import FFPROBE_PATH

FFMPEG = FFPROBE_PATH.replace('ffprobe', 'ffmpeg')


def trim_clip(source, output, segment_start, accepted_start, accepted_end):
    info = json.loads(subprocess.check_output([
        FFPROBE_PATH, '-v', 'error', '-select_streams', 'v:0',
        '-show_streams', '-show_frames', '-show_entries',
        'stream=time_base,start_pts:frame=best_effort_timestamp,duration',
        '-of', 'json', str(source),
    ], timeout=15))
    time_base = Fraction(info['streams'][0]['time_base'])
    origin = int(info['streams'][0]['start_pts']) * time_base
    start = Fraction(str(accepted_start)) - Fraction(str(segment_start))
    end = Fraction(str(accepted_end)) - Fraction(str(segment_start)) - Fraction(1, 1000)
    selected = []
    for index, frame in enumerate(info['frames']):
        if 'best_effort_timestamp' not in frame or 'duration' not in frame:
            continue
        pts = int(frame['best_effort_timestamp']) * time_base - origin
        duration = int(frame['duration']) * time_base
        if duration > 0 and start <= pts and pts + duration <= end:
            selected.append((index, pts, duration))
    if not selected:
        return None
    first, last = selected[0], selected[-1]
    if [frame[0] for frame in selected] != list(range(first[0], last[0] + 1)):
        raise ValueError('Noncontiguous or unknown frame timing')
    output = Path(output)
    try:
        subprocess.run([
            FFMPEG, '-v', 'error', '-threads', '1', '-i', str(source),
            '-map', '0:v:0', '-an', '-vf',
            f'select=between(n\\,{first[0]}\\,{last[0]}),setpts=PTS-STARTPTS',
            '-fps_mode', 'vfr', '-c:v', 'libx264', '-threads', '2',
            '-preset', 'ultrafast', '-crf', '16', '-movflags', '+faststart',
            '-y', str(output),
        ], check=True, timeout=45)
        actual = json.loads(subprocess.check_output([
            FFPROBE_PATH, '-v', 'error', '-select_streams', 'v:0',
            '-count_frames', '-show_entries',
            'stream=nb_read_frames,duration:format=duration',
            '-of', 'json', str(output),
        ], timeout=15))
        count = int(actual['streams'][0]['nb_read_frames'])
        length = Fraction(actual['format']['duration'])
        actual_start = Fraction(str(segment_start)) + first[1]
        if count != len(selected) or actual_start + length > Fraction(str(accepted_end)):
            raise ValueError('Encoded clip exceeds authorized frame count or time')
        return {
            'first_source_frame': first[0], 'last_source_frame': last[0],
            'frames': count, 'start': float(actual_start),
            'end': float(actual_start + length), 'duration': float(length),
        }
    except BaseException:
        output.unlink(missing_ok=True)
        raise


async def trim_clip_async(source, output, segment_start, accepted_start, accepted_end):
    # Frigate's recording process cannot safely create a ThreadPoolExecutor here.
    process = await asyncio.create_subprocess_exec(
        sys.executable, '-m', 'frigate.gecko_clip', str(source), str(output),
        str(segment_start), str(accepted_start), str(accepted_end),
        cwd=str(Path(__file__).resolve().parents[1]),
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
        start_new_session=True,
    )
    try:
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=60)
        if process.returncode:
            raise RuntimeError('Boundary encoder failed: ' + stderr.decode(errors='replace')[-500:])
        return json.loads(stdout)
    except BaseException:
        if process.returncode is None:
            os.killpg(process.pid, signal.SIGKILL)
            await process.wait()
        Path(output).unlink(missing_ok=True)
        raise


if __name__ == '__main__':
    print(json.dumps(trim_clip(
        sys.argv[1], sys.argv[2], float(sys.argv[3]),
        float(sys.argv[4]), float(sys.argv[5]),
    )))
