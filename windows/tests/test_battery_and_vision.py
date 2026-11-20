"""Unit tests for <=10% low-battery alert tracking and Vision AI false-positive filters."""

from __future__ import annotations

from dataclasses import dataclass
import unittest

from photopic_win.vision_autotagger import VisionAutoTaggerWin
from photopic_win.wpd_tether_service import LowBatteryAlertTrackerWin


@dataclass
class _FakeLandmark:
    x: float
    y: float
    visibility: float = 1.0


class TestBatteryAndVisionFilters(unittest.TestCase):
    def test_low_battery_tracker_threshold_and_hysteresis(self) -> None:
        tracker = LowBatteryAlertTrackerWin()
        self.assertFalse(tracker.evaluate("cam-1", None))
        self.assertFalse(tracker.evaluate("cam-1", 25))
        self.assertTrue(tracker.evaluate("cam-1", 10))
        self.assertFalse(tracker.evaluate("cam-1", 8))
        self.assertFalse(tracker.evaluate("cam-1", 12))
        self.assertFalse(tracker.evaluate("cam-1", 20))
        self.assertTrue(tracker.evaluate("cam-1", 5))
        tracker.sync_connected(set())
        self.assertTrue(tracker.evaluate("cam-1", 9))

    def test_vision_box_deduplication(self) -> None:
        boxes = [
            (0.20, 0.20, 0.20, 0.25),
            (0.21, 0.20, 0.20, 0.25),  # > 45% IoU overlap -> deduped
            (0.60, 0.20, 0.20, 0.25),  # distinct second face
        ]
        deduped = VisionAutoTaggerWin._dedupe_boxes(boxes)
        self.assertEqual(len(deduped), 2)

    def test_pose_ignores_occluded_low_visibility_landmarks(self) -> None:
        lm = [_FakeLandmark(0.5, 0.5, visibility=0.2) for _ in range(33)]
        # Put wrist above shoulder but with low visibility -> must NOT emit "Brazos arriba"
        lm[11] = _FakeLandmark(0.4, 0.4, visibility=0.2)
        lm[13] = _FakeLandmark(0.4, 0.3, visibility=0.2)
        lm[15] = _FakeLandmark(0.4, 0.2, visibility=0.2)
        self.assertEqual(VisionAutoTaggerWin._classify_pose_landmarks(lm), [])

        # Now mark shoulder, elbow, wrist visible -> must emit "Brazos arriba"
        lm[11].visibility = 0.9
        lm[13].visibility = 0.9
        lm[15].visibility = 0.9
        self.assertIn("Brazos arriba", VisionAutoTaggerWin._classify_pose_landmarks(lm))


if __name__ == "__main__":
    unittest.main()
