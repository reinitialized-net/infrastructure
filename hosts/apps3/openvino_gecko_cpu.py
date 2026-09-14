"""Experimental one-class gecko detector; not enabled in production.

Accept RGB uint8 regions from Frigate and resize to the exported network's input
size before normalizing. The model checksum, shape, class count, and input
contract must match. This adapter does not qualify the model's accuracy.
"""

import hashlib
from pathlib import Path
import time
from typing import Literal

import cv2
import numpy as np
import openvino as ov
from pydantic import Field

from frigate.detectors.detection_api import DetectionApi
from frigate.gecko_recording_health import DETECTOR_HEARTBEAT, heartbeat
from frigate.detectors.detector_config import (
    BaseDetectorConfig, InputDTypeEnum, ModelTypeEnum,
)


class GeckoCpuConfig(BaseDetectorConfig):
    type: Literal["openvino_gecko_cpu"]
    model_sha256: str = Field(pattern=r"^[0-9a-f]{64}$")
    num_threads: int = Field(default=2, ge=1, le=4)
    min_score: float = Field(default=0.15, ge=0.05, le=0.99)


class GeckoCpu(DetectionApi):
    type_key = "openvino_gecko_cpu"
    supported_models = [ModelTypeEnum.yologeneric]

    def __init__(self, detector_config: GeckoCpuConfig):
        super().__init__(detector_config)
        model = detector_config.model
        if model.model_type != ModelTypeEnum.yologeneric:
            raise ValueError("Only qualified one-class YOLO models are supported")
        if (
            model.input_tensor != "nhwc" or model.input_pixel_format != "rgb"
            or model.input_dtype != InputDTypeEnum.int
        ):
            raise ValueError("Adapter input must be NHWC RGB uint8")
        if model.width != model.height:
            raise ValueError("Square source regions are required")
        if hashlib.sha256(Path(model.path).read_bytes()).hexdigest() != detector_config.model_sha256:
            raise ValueError("Gecko model checksum mismatch")

        core = ov.Core()
        self.compiled = core.compile_model(
            model.path, "CPU", {
                "INFERENCE_NUM_THREADS": detector_config.num_threads,
                "NUM_STREAMS": 1,
                "ENABLE_CPU_PINNING": False,
                "INFERENCE_PRECISION_HINT": "f32",
            },
        )
        if len(self.compiled.inputs) != 1 or len(self.compiled.outputs) != 1:
            raise ValueError("Expected one model input and one model output")
        shape = list(self.compiled.input(0).shape)
        output = list(self.compiled.output(0).shape)
        if (
            len(shape) != 4 or shape[:2] != [1, 3] or shape[2] != shape[3]
            or self.compiled.input(0).get_element_type() != ov.Type.f32
        ):
            raise ValueError("Expected a square NCHW float32 model input")
        if len(output) != 3 or output[:2] != [1, 5]:
            raise ValueError("Expected exactly one gecko class and raw YOLO output")
        self.side = shape[2]
        self.source_side = model.width
        self.min_score = detector_config.min_score
        self.request = self.compiled.create_infer_request()
        self.last_heartbeat = 0.0
        for _ in range(3):
            self.detect_raw(np.zeros((1, self.source_side, self.source_side, 3), np.uint8))

    def tensor(self, tensor_input):
        if (
            tensor_input.dtype != np.uint8
            or tensor_input.shape != (1, self.source_side, self.source_side, 3)
        ):
            raise ValueError("Unexpected source input shape or dtype")
        rgb = tensor_input[0]
        if self.side != self.source_side:
            rgb = cv2.resize(rgb, (self.side, self.side), interpolation=cv2.INTER_LINEAR)
        return np.ascontiguousarray(rgb.transpose(2, 0, 1)[None], dtype=np.float32) / 255

    def infer(self, tensor_input):
        result = self.request.infer({0: self.tensor(tensor_input)})
        now = time.monotonic()
        if now - self.last_heartbeat >= 5:
            heartbeat(DETECTOR_HEARTBEAT)
            self.last_heartbeat = now
        return result[self.compiled.output(0)].copy()

    def detect_raw(self, tensor_input):
        predictions = self.infer(tensor_input)[0].T
        valid = (
            np.isfinite(predictions).all(axis=1)
            & (predictions[:, 4] >= self.min_score) & (predictions[:, 4] <= 1)
            & (predictions[:, 2] > 0) & (predictions[:, 3] > 0)
        )
        predictions = predictions[valid]
        output = np.zeros((20, 6), np.float32)
        if not len(predictions):
            return output
        xywh = np.column_stack((
            predictions[:, 0] - predictions[:, 2] / 2,
            predictions[:, 1] - predictions[:, 3] / 2,
            predictions[:, 2], predictions[:, 3],
        ))
        indices = cv2.dnn.NMSBoxes(
            xywh.tolist(), predictions[:, 4].tolist(), self.min_score, 0.7,
        )
        for row, index in enumerate(np.asarray(indices).reshape(-1)[:20]):
            x, y, width, height = xywh[index]
            x1, y1, x2, y2 = np.clip([x, y, x + width, y + height], 0, self.side)
            output[row] = [
                0, predictions[index, 4],
                y1 / self.side, x1 / self.side, y2 / self.side, x2 / self.side,
            ]
        return output
