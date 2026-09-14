"""Probe Frigate 0.18 recording semantics; passing is NOT gecko qualification.

Run with the pinned image's Python and PYTHONPATH=/opt/frigate. Calls upstream
decision methods with synthetic metadata; media/database writes are replaced
by in-memory sinks. No live config, camera, recordings, or models are modified.
These checks demonstrate why a label and post_capture change is insufficient.
"""

import asyncio
from datetime import datetime, timezone
from types import SimpleNamespace as NS
import unittest
from unittest.mock import patch

from frigate.config.camera.record import RecordConfig, RetainModeEnum
from frigate.config.camera.review import ReviewConfig
from frigate.output.preview import PreviewRecorder
from frigate.record.maintainer import RecordingMaintainer, SegmentInfo
from frigate.review.maintainer import ActiveObjects, PendingReviewSegment
from frigate.review.types import SeverityEnum


def camera():
    return NS(
        record=RecordConfig(enabled=True),
        detect=NS(stationary=NS(threshold=50)),
        review=ReviewConfig(
            alerts={"enabled": False},
            detections={"enabled": True, "labels": ["gecko"]},
        ),
    )


def tracked(**changes):
    return dict(
        dict(
            id="synthetic-gecko", label="gecko", frame_time=100.0,
            motionless_count=0, position_changes=1, pending_loitering=False,
            false_positive=False, current_zones=[],
        ),
        **changes,
    )


def retained_segment(record, start, end, reviews, motion=0):
    """Exercise the real retention decision without accessing media or the DB."""
    start_dt = datetime.fromtimestamp(start, timezone.utc)
    end_dt = datetime.fromtimestamp(end, timezone.utc)
    maintainer = RecordingMaintainer.__new__(RecordingMaintainer)
    maintainer.config = NS(cameras={"test": NS(record=record)})
    maintainer.end_time_cache = {"synthetic.mp4": (end_dt, end - start)}
    maintainer.object_recordings_info = {"test": [(end + 100,)]}
    maintainer.segment_stats = lambda *args: SegmentInfo(motion, 0, 0, 0)
    maintainer.drop_segment = lambda path: None

    async def move(camera_name, actual_start, actual_end, *args):
        return (actual_start.timestamp(), actual_end.timestamp())

    maintainer.move_segment = move
    return asyncio.run(maintainer.validate_and_move_segment(
        "test", reviews, {"cache_path": "synthetic.mp4", "start_time": start_dt},
    ))


class RecordingSemantics(unittest.TestCase):
    def test_motion_retention_keeps_unclassified_motion(self):
        record = RecordConfig(enabled=True, motion={"days": 30})
        self.assertEqual(retained_segment(record, 100, 105, [], motion=1), (100, 105))
        record.motion.days = 0
        self.assertIsNone(retained_segment(record, 100, 105, [], motion=1))

    def test_retention_mode_can_discard_the_quiet_tail(self):
        quiet = SegmentInfo(0, 0, 0, 0)
        self.assertTrue(quiet.should_discard_segment(RetainModeEnum.motion))
        self.assertTrue(quiet.should_discard_segment(RetainModeEnum.active_objects))
        self.assertFalse(quiet.should_discard_segment(RetainModeEnum.all))

    def test_review_requires_gecko_activity(self):
        config = camera()
        self.assertTrue(ActiveObjects(100, config, [tracked()]).has_active_objects())
        for changes in (
            {"label": "person"}, {"false_positive": True},
            {"frame_time": 99}, {"motionless_count": 50},
            {"position_changes": 0},
        ):
            with self.subTest(changes=changes):
                self.assertFalse(ActiveObjects(
                    100, config, [tracked(**changes)],
                ).has_active_objects())

    def test_review_end_is_last_activity_not_publication_time(self):
        segment = PendingReviewSegment(
            "test", 100, SeverityEnum.detection,
            {"synthetic-gecko": "gecko"}, {}, [], set(),
        )
        segment.last_detection_time = 110
        self.assertEqual(segment.get_data(ended=True)["end_time"], 110)

    def test_segments_are_not_trimmed_to_the_event_window(self):
        record = RecordConfig(enabled=True, detections={
            "pre_capture": 0, "post_capture": 0,
            "retain": {"days": 30, "mode": "all"},
        })
        review = NS(severity="detection", start_time=100, end_time=130)
        self.assertEqual(retained_segment(record, 98, 103, [review]), (98, 103))
        self.assertEqual(retained_segment(record, 129, 134, [review]), (129, 134))
        self.assertIsNone(retained_segment(record, 134, 139, [review]))

    def test_open_review_keeps_quiet_segments_until_closed(self):
        record = RecordConfig(enabled=True, detections={"retain": {"mode": "all"}})
        review = NS(severity="detection", start_time=100, end_time=None)
        self.assertEqual(retained_segment(record, 1000, 1005, [review]), (1000, 1005))

    def test_previews_include_unrelated_motion_and_periodic_idle_frames(self):
        recorder = NS(config=camera(), last_output_time=0)
        self.assertTrue(PreviewRecorder.should_write_frame(recorder, [], [[1, 1, 2, 2]], 1))
        self.assertTrue(PreviewRecorder.should_write_frame(recorder, [], [], 32))
        recorder.config.record.enabled = False
        self.assertFalse(PreviewRecorder.should_write_frame(recorder, [], [], 64))

    def test_disabled_recording_still_bootstraps_and_converts_preview(self):
        writes = []
        recorder = NS(
            config=camera(), start_time=0, output_frames=[], segment_end=3600,
            requestor=None, reset_frame_cache=lambda timestamp: None,
            write_frame_to_cache=lambda timestamp, frame: writes.append(timestamp),
        )
        recorder.config.record.enabled = False
        PreviewRecorder.write_data(recorder, [], [], 100, None)
        self.assertEqual(writes, [100])
        with patch("frigate.output.preview.FFMpegConverter") as converter:
            PreviewRecorder.write_data(recorder, [], [], 3600, None)
            converter.return_value.start.assert_called_once()
        self.assertEqual(writes, [100, 3600])


if __name__ == "__main__":
    unittest.main(verbosity=2)
