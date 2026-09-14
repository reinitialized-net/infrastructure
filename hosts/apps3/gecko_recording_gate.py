"""Retention gate for confirmed gecko tracks.

Consumes confirmed Frigate/Norfair tracks, NOT raw model predictions. Movement
must already have been established by the tracker. This module proves temporal
retention behavior, not recognition or movement-classification accuracy.

Only fully observed intervals can be retained. Whole video segments crossing a
boundary are rejected; this conservative implementation can omit edge footage.
"""

from dataclasses import dataclass
import math
from numbers import Integral, Real


def _finite_number(value):
    return isinstance(value, Real) and not isinstance(value, bool) and math.isfinite(value)


def _same_site(a, b):
    overlap = max(0, min(a[2], b[2]) - max(a[0], b[0])) * max(
        0, min(a[3], b[3]) - max(a[1], b[1])
    )
    area_a = (a[2] - a[0]) * (a[3] - a[1])
    area_b = (b[2] - b[0]) * (b[3] - b[1])
    # Native crops can alternate between the whole animal and its torso.
    # That localization change must not create another quiet allowance.
    return (
        overlap / (area_a + area_b - overlap) >= 0.7
        or (max(area_a, area_b) <= 4 * min(area_a, area_b)
            and overlap / min(area_a, area_b) >= 0.85)
    )


@dataclass
class _Track:
    box: tuple[float, float, float, float]
    last_seen: float
    deadline: float


class GeckoRecordingGate:
    """One camera and one uninterrupted capture-clock epoch.

    The caller must reset this object after a capture-clock discontinuity and
    discard segments belonging to the previous epoch. Track-ID changes at the
    same position inherit the existing deadline. Ambiguous associations fail
    closed. A new gate contains no accepted history.
    """

    def __init__(self, *, quiet_seconds=30.0, max_frame_gap=1.0, history_seconds=120.0, min_score=0.5):
        if not (0 < quiet_seconds <= 30 and 0 < max_frame_gap <= 1):
            raise ValueError("Invalid timing bounds")
        if not math.isfinite(history_seconds) or history_seconds < 60:
            raise ValueError("Invalid history bound")
        if not _finite_number(min_score) or not 0 < min_score <= 1:
            raise ValueError("Invalid recording confidence threshold")
        self.min_score = min_score
        self.quiet_seconds = quiet_seconds
        self.max_frame_gap = max_frame_gap
        self.history_seconds = history_seconds
        self.last_frame = None
        self.last_accepted = None
        self.last_deadline = None
        self.quiet_deadline = None
        self.windows = []
        self.tracks = []
        self.identities = {}

    def _valid_object(self, obj, frame_time):
        if not isinstance(obj, dict):
            return False
        if (
            obj.get("label") != "gecko"
            or obj.get("false_positive") is not False
            # Frigate keeps false_positive=False permanently after confirmation.
            # A low-confidence background association must not authorize video.
            or not _finite_number(obj.get("score"))
            or not self.min_score <= obj["score"] <= 1
            or obj.get("frame_time") != frame_time
            or not isinstance(obj.get("id"), str)
            or not obj["id"]
        ):
            return False
        box = obj.get("box")
        if not isinstance(box, (list, tuple)) or len(box) != 4:
            return False
        if not all(_finite_number(v) for v in box):
            return False
        return (
            box[2] > box[0] and box[3] > box[1]
            and isinstance(obj.get("motionless_count"), Integral)
            and not isinstance(obj["motionless_count"], bool)
            and obj["motionless_count"] >= 0
            and isinstance(obj.get("position_changes"), Integral)
            and not isinstance(obj["position_changes"], bool)
            and obj["position_changes"] >= 0
        )

    def observe(self, frame_time, objects):
        """Append one complete frame; duplicate/out-of-order frames do nothing.

        Frame timestamps use the same clock as recording segment timestamps.
        No extrapolated tail is authorized: later positive observations must
        actually cover the segment before ``allows`` can return true.
        """
        if not _finite_number(frame_time):
            return
        if self.last_frame is not None and frame_time <= self.last_frame:
            return
        previous_frame = self.last_frame
        self.last_frame = frame_time
        self.windows = [w for w in self.windows if w[1] >= frame_time - self.history_seconds]
        self.identities = {
            key: state for key, state in self.identities.items()
            if state.last_seen >= frame_time - self.history_seconds
        }
        self.tracks = [s for s in self.tracks if s.last_seen >= frame_time - self.history_seconds]

        accepted = False
        accepted_deadline = None
        new_site = False
        movement = False
        used = set()
        for obj in objects:
            if not self._valid_object(obj, frame_time):
                continue
            box = tuple(obj["box"])
            created_site = False
            state = self.identities.get(obj["id"])
            if state is None:
                matches = [s for s in self.tracks if _same_site(box, s.box)]
                if len(matches) > 1:
                    continue
                if matches:
                    state = matches[0]
                else:
                    if len(self.tracks) >= 64:
                        continue
                    state = _Track(box, frame_time, frame_time + self.quiet_seconds)
                    self.tracks.append(state)
                    created_site = True
                # Bound churn without evicting still-visible track deadlines.
                if len(self.identities) >= 256:
                    continue
                self.identities[obj["id"]] = state
            if id(state) in used:
                continue
            new_site = new_site or created_site
            used.add(id(state))
            state.box = box
            state.last_seen = frame_time
            # A newly assigned tracker ID starts with zero position changes;
            # this must not restart a stationary object's quiet deadline.
            if obj["motionless_count"] == 0 and obj["position_changes"] > 0:
                state.deadline = frame_time + self.quiet_seconds
                movement = True
            if frame_time <= state.deadline:
                accepted = True
                accepted_deadline = max(accepted_deadline or state.deadline, state.deadline)

        # Discovering another already-still gecko during the same recording
        # must not extend its quiet tail. Only verified movement can do that.
        # A genuinely new site may begin a later recording after the old tail
        # expires; existing IDs and spatial aliases cannot rearm it.
        if accepted and (
            self.quiet_deadline is None or movement
            or (
                new_site and frame_time > self.quiet_deadline
                and (
                    self.last_accepted is None
                    or previous_frame is None
                    or frame_time - previous_frame > self.max_frame_gap
                )
            )
        ):
            self.quiet_deadline = frame_time + self.quiet_seconds
        if accepted:
            accepted_deadline = min(accepted_deadline, self.quiet_deadline)
            accepted = frame_time <= accepted_deadline

        continuous = (
            accepted and previous_frame is not None
            and self.last_accepted == previous_frame
            and frame_time - previous_frame <= self.max_frame_gap
            and self.last_deadline is not None and frame_time <= self.last_deadline
        )
        if accepted:
            if continuous and self.windows:
                self.windows[-1] = (self.windows[-1][0], frame_time)
            else:
                self.windows.append((frame_time, frame_time))
            self.last_accepted = frame_time
            self.last_deadline = accepted_deadline
        else:
            self.last_accepted = None
            self.last_deadline = None

    def allows(self, start, end):
        """Whether an entire finalized segment is covered by accepted frames."""
        if not all(_finite_number(v) for v in [start, end]):
            return False
        return end > start and any(a <= start and end <= b for a, b in self.windows)

    def accepted_intervals(self, start, end):
        """Observed intersections for a caller that can safely trim video frames.

        This does not authorize writing an entire overlapping segment. The caller
        must wait for observations through the segment end (or its input timeout),
        then retain only decoded frames wholly contained in these intervals.
        """
        if not all(_finite_number(v) for v in (start, end)) or end <= start:
            return []
        return [
            (max(start, a), min(end, b))
            for a, b in self.windows
            if max(start, a) < min(end, b)
        ]
