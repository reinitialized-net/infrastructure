"""Experimental gecko movement check for the pinned Frigate 0.18 image.

This checks image changes, not object identity.
The caller must supply real gecko tracks and qualify the thresholds on footage.
Camera registration uses background feature consensus so camera drift and box
jitter do not, by themselves, become gecko movement. Uncertain registration
resets image anchors without reporting movement or renewing recording deadlines.
"""

import math

import cv2
import numpy as np

from frigate.track.stationary_classifier import StationaryMotionClassifier
from frigate.gecko_presence import GeckoPresence


class GeckoVisualMotion:
    def __init__(self):
        self.classifier = StationaryMotionClassifier()
        self.presence = GeckoPresence()
        # Experimental values; synthetic checks do not qualify real-motion recall.
        self.classifier.NCC_KEEP_THRESHOLD = 0.995
        self.classifier.NCC_ACTIVE_THRESHOLD = 0.985
        self.classifier.SHIFT_KEEP_THRESHOLD = 0.005
        self.classifier.SHIFT_ACTIVE_THRESHOLD = 0.01
        self.classifier.DRIFT_ACTIVE_THRESHOLD = 0.04
        self.reference = None
        self.reference_points = None
        self.last_frame = None
        self.frame_time = None
        self.current = None
        self.last_seen = {}
        self.suppress = True

    def _register(self, small, scale):
        """Fit camera movement from features that agree in both directions."""
        if self.reference_points is None or len(self.reference_points) < 20:
            return None
        reference = self.reference.astype(np.uint8)
        current = small.astype(np.uint8)
        points, status, _ = cv2.calcOpticalFlowPyrLK(
            reference, current, self.reference_points, None,
            winSize=(21, 21), maxLevel=3,
        )
        if points is None or status is None:
            return None
        back, reverse_status, _ = cv2.calcOpticalFlowPyrLK(
            current, reference, points, None, winSize=(21, 21), maxLevel=3,
        )
        if back is None or reverse_status is None:
            return None
        good = (
            (status[:, 0] > 0)
            & (reverse_status[:, 0] > 0)
            & (np.linalg.norm(back[:, 0] - self.reference_points[:, 0], axis=1) < 0.5)
        )
        if np.count_nonzero(good) < 20:
            return None
        warp, inliers = cv2.estimateAffinePartial2D(
            self.reference_points[good], points[good], method=cv2.RANSAC,
            ransacReprojThreshold=0.5, maxIters=500, confidence=0.99,
        )
        if warp is None or inliers is None or not np.isfinite(warp).all():
            return None
        singular = np.linalg.svd(warp[:, :2], compute_uv=False)
        if (
            inliers.mean() < 0.7
            or singular.min() < 0.97 or singular.max() > 1.03
            or np.linalg.norm(warp[:, 2] * scale) > 12
        ):
            return None
        return warp

    def begin_frame(self, frame_time, yuv):
        """Prepare one frame. Missing, stale, or discontinuous input cannot move a track."""
        self.current = None
        self.suppress = True
        if (
            not isinstance(frame_time, (int, float)) or not math.isfinite(frame_time)
            or (self.last_frame is not None and frame_time <= self.last_frame)
            or yuv is None
        ):
            return
        height = yuv.shape[0] * 2 // 3
        width = yuv.shape[1]
        scale = np.array([width / 180, height / 320])
        small = cv2.resize(
            yuv[:height], (180, 320), interpolation=cv2.INTER_AREA,
        ).astype(np.float32)
        gap = self.last_frame is not None and frame_time - self.last_frame > 1
        reset = (
            self.reference is None or self.last_frame is None
            or abs(float(np.median(small - self.reference))) > 3
        )
        warp = None
        if not reset:
            try:
                warp = self._register(small, scale)
            except cv2.error:
                pass
            reset = warp is None
        if reset:
            self.reference = small.copy()
            self.reference_points = cv2.goodFeaturesToTrack(
                small.astype(np.uint8), maxCorners=200,
                qualityLevel=0.01, minDistance=5,
            )
            warp = np.eye(2, 3, dtype=np.float32)
            for identity in self.last_seen:
                self.classifier.reset(identity)
        # A processing gap does not erase a still-valid spatial registration.
        # Suppress movement across the gap, but preserve departure evidence when
        # the current background still registers against the original image.
        self.suppress = reset or gap
        scaled = warp.copy()
        scaled[0, 1] *= scale[0] / scale[1]
        scaled[1, 0] *= scale[1] / scale[0]
        scaled[:, 2] *= scale
        self.inverse = cv2.invertAffineTransform(scaled)
        self.current = yuv.copy()
        self.current[:height] = cv2.warpAffine(
            yuv[:height], scaled, (width, height),
            flags=cv2.INTER_LINEAR | cv2.WARP_INVERSE_MAP,
            borderMode=cv2.BORDER_REPLICATE,
        )
        self.presence.begin(self.current[:height], frame_time, reset)
        self.last_frame = self.frame_time = frame_time
        for identity in list(self.last_seen):
            if frame_time - self.last_seen[identity] > 120:
                self.forget(identity)

    def forget(self, identity):
        self.last_seen.pop(identity, None)
        for attribute in ("anchor_crops", "anchor_boxes", "changed_counts", "shift_histories"):
            getattr(self.classifier, attribute).pop(identity, None)

    def moved(self, identity, yuv, box):
        """Check the fixed image anchor, not changes to the detector's box.

        The YUV argument mirrors the caller's current-frame availability; image
        comparison uses the camera-stabilized frame prepared by ``begin_frame``.
        """
        if self.current is None or yuv is None:
            return False
        if identity not in self.last_seen and len(self.last_seen) >= 64:
            return False
        corners = np.array([
            [box[0], box[1], 1], [box[2], box[1], 1],
            [box[0], box[3], 1], [box[2], box[3], 1],
        ]) @ self.inverse.T
        if not np.isfinite(corners).all():
            return False
        anchored_box = (
            int(corners[:, 0].min()), int(corners[:, 1].min()),
            int(corners[:, 0].max()), int(corners[:, 1].max()),
        )
        if anchored_box[2] <= anchored_box[0] or anchored_box[3] <= anchored_box[1]:
            return False
        returned = self.presence.confirm(identity, anchored_box)
        self.last_seen[identity] = self.frame_time
        if self.suppress:
            self.classifier.reset(identity)
            self.classifier.ensure_anchor(identity, self.current, anchored_box)
            return False
        self.classifier.ensure_anchor(identity, self.current, anchored_box)
        moved = returned or not self.classifier.evaluate(identity, self.current, anchored_box)
        if moved:
            self.classifier.reset(identity)
            self.classifier.ensure_anchor(identity, self.current, anchored_box)
        return moved
