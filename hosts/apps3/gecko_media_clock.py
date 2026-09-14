"""Experimental shared presentation clock for gecko detection and recording.

NUT carries decoded frame PTS. The segment muxer's CSV carries recording PTS.
A per-process epoch gives both the same calendar origin; filename seconds never
participate in authorization. All clock metadata stays in the volatile cache.
"""
import csv
import json
import math
from pathlib import Path
import time
import uuid

import av

CACHE = Path('/tmp/cache')
CAMERA = 'camera_13_37'
MARKER = CACHE / (CAMERA+'-gecko-clock.json')
PLACEHOLDER = str(CACHE / (CAMERA+'-gecko-segments.csv'))


def prepare_command(command):
    if command.count(PLACEHOLDER) != 1:
        raise ValueError('Missing unique gecko segment clock output')
    epoch = uuid.uuid4().hex
    csv_path = CACHE / (CAMERA+'-gecko-'+epoch+'.csv')
    MARKER.unlink(missing_ok=True)
    for old in CACHE.glob(CAMERA+'-gecko-*.csv'):
        old.unlink(missing_ok=True)
    for old in CACHE.glob(CAMERA+'@*.mp4'):
        old.unlink(missing_ok=True)
    return [str(csv_path) if part == PLACEHOLDER else part for part in command], {'epoch':epoch, 'csv':str(csv_path)}


class GeckoFrameReader:
    def __init__(self, stream, context, shape):
        self.container = av.open(stream, format='nut')
        self.frames = iter(self.container.decode(video=0))
        self.context = context
        self.shape = shape
        self.last_pts = None
        self.base = None

    def read(self):
        frame = next(self.frames)
        if frame.pts is None or frame.time_base is None:
            raise ValueError('Missing gecko presentation timestamp')
        pts = float(frame.pts*frame.time_base)
        if not math.isfinite(pts) or (self.last_pts is not None and (pts <= self.last_pts or pts-self.last_pts > 2)):
            raise ValueError('Gecko media clock discontinuity')
        pixels = frame.to_ndarray(format='yuv420p')
        if pixels.shape != self.shape:
            raise ValueError('Unexpected gecko frame shape')
        if self.base is None:
            self.base = time.time()-pts
            data = {**self.context, 'base':self.base, 'first_pts':pts, 'created':time.time()}
            temporary = MARKER.with_suffix('.new')
            temporary.write_text(json.dumps(data))
            temporary.replace(MARKER)
        self.last_pts = pts
        return pixels.tobytes(), self.base+pts

    def close(self):
        self.container.close()


def read_clock():
    try:
        data = json.loads(MARKER.read_text())
        if (not isinstance(data['epoch'],str) or len(data['epoch']) != 32
            or not math.isfinite(data['base'])
            or data['csv'] != str(CACHE/(CAMERA+'-gecko-'+data['epoch']+'.csv'))):
            return None
        return data
    except (OSError, ValueError, KeyError, TypeError):
        return None


def segment_clock(clock, cache_path):
    try:
        path = Path(clock['csv'])
        if path.stat().st_size > 65536:
            return None
        rows = list(csv.reader(path.read_text().splitlines()))
        matches=[]
        for row in rows:
            if len(row) != 3 or Path(row[0]).name != Path(cache_path).name:
                continue
            start,end = float(row[1]),float(row[2])
            if all(math.isfinite(t) for t in (start,end)) and 0 < end-start < 60:
                # The first RTSP segment's CSV origin can precede its first
                # packet. reset_timestamps preserves that gap in stream.start_time.
                # Later segments normally have a zero local stream origin.
                with av.open(str(cache_path)) as media:
                    stream = media.streams.video[0]
                    if stream.start_time is None or stream.duration is None:
                        return None
                    offset = float(stream.start_time * stream.time_base)
                    duration = float(stream.duration * stream.time_base)
                if (not all(math.isfinite(t) for t in (offset, duration))
                    or offset < 0 or duration <= 0
                    or abs(end-start-offset-duration) > 0.002):
                    return None
                # MP4 edit lists round the offset to milliseconds. CSV end
                # minus stream duration retains the original packet precision.
                matches.append((clock['base']+end-duration,clock['base']+end))
        return matches[0] if len(matches)==1 else None
    except (OSError, ValueError, TypeError, KeyError, IndexError, csv.Error, av.error.FFmpegError):
        return None
