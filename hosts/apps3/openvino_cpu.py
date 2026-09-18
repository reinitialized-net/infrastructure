"""Frigate 0.18 CPU detector adapter for apps3's four-core VM.

Use three inference threads without pinning, leaving capacity for video work
and other services. Model loading and output decoding stay with the stock
OpenVINO detector; only the compiled-model scheduling is replaced.
This module is discovered by Frigate's detector plugin registry.
"""

from typing import Literal

import numpy as np
import openvino as ov
from pydantic import Field

from frigate.detectors.detection_api import DetectionApi
from frigate.detectors.detector_config import BaseDetectorConfig, ModelTypeEnum
from frigate.detectors.plugins.openvino import OvDetector


class OpenVinoCpuConfig(BaseDetectorConfig):
    """OpenVINO CPU with explicit inference scheduling."""

    type: Literal["openvino_cpu"]
    device: Literal["CPU"] = "CPU"
    num_threads: int = Field(default=3, ge=1, le=4)


class OpenVinoCpu(DetectionApi):
    type_key = "openvino_cpu"
    supported_models = [ModelTypeEnum.ssd, ModelTypeEnum.yologeneric]

    def __init__(self, detector_config: OpenVinoCpuConfig):
        super().__init__(detector_config)
        if detector_config.model.model_type not in self.supported_models:
            raise ValueError("The apps3 CPU adapter supports only SSD and yolo-generic models")
        self.detector = OvDetector(detector_config)
        if self.detector.model_invalid:
            raise ValueError("Invalid detection model")

        runner = self.detector.runner
        runner.compiled_model = runner.ov_core.compile_model(
            model=detector_config.model.path,
            device_name="CPU",
            config={
                "INFERENCE_NUM_THREADS": detector_config.num_threads,
                "NUM_STREAMS": 1,
                "ENABLE_CPU_PINNING": False,
            },
        )
        runner.infer_request = runner.compiled_model.create_infer_request()
        port = runner.compiled_model.input(0)
        runner.input_tensor = ov.Tensor(port.get_element_type(), port.get_shape())

        # Complete lazy kernel initialization before accepting camera work.
        # No live inference timing or warning threshold is modified.
        warmup = np.zeros(port.get_shape(), dtype=port.get_element_type().to_dtype())
        for _ in range(3):
            self.detector.detect_raw(warmup)

    def detect_raw(self, tensor_input):
        return self.detector.detect_raw(tensor_input)
