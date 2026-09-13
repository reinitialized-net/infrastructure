"""Run inside the pinned Frigate image with the managed CPU plugin installed.

PYTHONPATH=/opt/frigate python3 /tmp/test_openvino_cpu.py
"""

import unittest

import numpy as np
from pydantic import ValidationError

from frigate.detectors import create_detector
from frigate.detectors.detector_config import ModelConfig
from frigate.detectors.plugins.openvino import OvDetector, OvDetectorConfig
from frigate.detectors.plugins.openvino_cpu import OpenVinoCpuConfig


class CpuDetectorQualification(unittest.TestCase):
    def test_registry_scheduling_and_detection_parity(self):
        model = ModelConfig(
            path="/openvino-model/ssdlite_mobilenet_v2.xml",
            labelmap_path="/openvino-model/coco_91cl_bkgr.txt",
            width=300,
            height=300,
            input_tensor="nhwc",
            input_pixel_format="bgr",
        )
        stock = OvDetector(OvDetectorConfig(type="openvino", device="CPU", model=model))
        managed = create_detector(OpenVinoCpuConfig(type="openvino_cpu", model=model))
        compiled = managed.detector.runner.compiled_model
        self.assertEqual(compiled.get_property("INFERENCE_NUM_THREADS"), 3)
        self.assertEqual(compiled.get_property("NUM_STREAMS"), 1)
        self.assertFalse(compiled.get_property("ENABLE_CPU_PINNING"))

        rng = np.random.default_rng(1337)
        for frame in (
            np.zeros((1, 300, 300, 3), dtype=np.uint8),
            rng.integers(0, 256, size=(1, 300, 300, 3), dtype=np.uint8),
            np.tile(np.arange(300, dtype=np.uint8)[None, :, None], (300, 1, 3))[None],
        ):
            np.testing.assert_allclose(
                managed.detect_raw(frame), stock.detect_raw(frame), rtol=1e-5, atol=1e-5
            )

    def test_gpu_and_oversubscription_rejected(self):
        for overrides in ({"device": "GPU"}, {"num_threads": 0}, {"num_threads": 5}):
            with self.assertRaises(ValidationError):
                OpenVinoCpuConfig(type="openvino_cpu", **overrides)


if __name__ == "__main__":
    unittest.main()
