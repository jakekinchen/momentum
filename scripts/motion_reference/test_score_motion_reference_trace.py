#!/usr/bin/env python3
"""Tests for motion-reference detector and kinematic scorecards."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

import score_motion_reference_trace as scorecards  # noqa: E402


def raw_pose(frame_id: int, offset: float = 0.0) -> dict[str, object]:
    landmarks = []
    for index in range(len(scorecards.LANDMARK_NAMES)):
        landmarks.append(
            {
                "x": 0.25 + (index % 5) * 0.06 + offset,
                "y": 0.20 + (index // 5) * 0.05,
                "z": 0.0,
                "visibility": 0.9,
                "presence": 0.9,
            }
        )
    return {
        "type": "pose",
        "frame_id": frame_id,
        "timestamp_ms": frame_id * 100,
        "image_size": [1280, 720],
        "poses_detected": 1,
        "landmarks": landmarks,
        "world_landmarks": [],
    }


def normalized_hold(frame_id: int) -> dict[str, object]:
    landmarks = {
        "primary.shoulder": {"x": 0.25, "y": 0.35, "z": 0, "visibility": 0.9, "presence": 0.9},
        "primary.elbow": {"x": 0.20, "y": 0.52, "z": 0, "visibility": 0.9, "presence": 0.9},
        "primary.wrist": {"x": 0.30, "y": 0.52, "z": 0, "visibility": 0.9, "presence": 0.9},
        "primary.hip": {"x": 0.55, "y": 0.36, "z": 0, "visibility": 0.9, "presence": 0.9},
        "primary.knee": {"x": 0.76, "y": 0.39, "z": 0, "visibility": 0.9, "presence": 0.9},
        "primary.ankle": {"x": 0.92, "y": 0.40, "z": 0, "visibility": 0.9, "presence": 0.9},
        "primary.foot.index": {"x": 0.96, "y": 0.43, "z": 0, "visibility": 0.9, "presence": 0.9},
        "secondary.elbow": {"x": 0.22, "y": 0.54, "z": 0, "visibility": 0.8, "presence": 0.8},
        "secondary.foot.index": {"x": 0.96, "y": 0.45, "z": 0, "visibility": 0.8, "presence": 0.8},
    }
    return {
        "type": "motion_demo_pose",
        "exercise_id": "bodyweight_plank",
        "frame_id": frame_id,
        "timestamp_ms": frame_id * 100,
        "phase": "hold",
        "primary_side": "left",
        "landmarks": landmarks,
    }


class MotionReferenceScorecardTests(unittest.TestCase):
    def test_detector_scorecard_is_honest_about_single_detector(self) -> None:
        scorecard = scorecards.detector_scorecard(
            [raw_pose(0), raw_pose(1, offset=0.002), raw_pose(2, offset=0.004)],
            ["mediapipe"],
        )

        self.assertEqual(scorecard["status"], "failed")
        self.assertIn(
            "requires_at_least_two_detectors_for_agreement",
            scorecard["review"]["failure_reasons"],
        )
        self.assertEqual(scorecard["metrics"]["frame_coverage"], 1.0)
        self.assertGreater(scorecard["metrics"]["mean_visibility"], 0.8)
        self.assertIn("temporal_jitter", scorecard["metrics"])

    def test_kinematic_scorecard_passes_static_hold_consistency(self) -> None:
        scorecard = scorecards.kinematic_scorecard(
            [normalized_hold(0), normalized_hold(1), normalized_hold(2)]
        )

        self.assertEqual(scorecard["status"], "passed")
        self.assertEqual(scorecard["metrics"]["loop_boundary_delta"], 0.0)
        self.assertEqual(scorecard["metrics"]["contact_lock_delta"], 0.0)
        self.assertEqual(scorecard["metrics"]["phase_monotonicity"], 1.0)
        self.assertEqual(scorecard["review"]["failure_reasons"], [])

    def test_main_writes_scorecard_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            raw = root / "raw.jsonl"
            normalized = root / "normalized.jsonl"
            raw.write_text(
                "\n".join(json.dumps(raw_pose(index)) for index in range(2)) + "\n",
                encoding="utf-8",
            )
            normalized.write_text(
                "\n".join(json.dumps(normalized_hold(index)) for index in range(2)) + "\n",
                encoding="utf-8",
            )

            result = scorecards.main(
                [
                    "--raw",
                    str(raw),
                    "--normalized",
                    str(normalized),
                    "--output-dir",
                    str(root / "out"),
                ]
            )

            self.assertEqual(result, 0)
            self.assertTrue((root / "out" / "detector_agreement_scorecard.json").exists())
            self.assertTrue((root / "out" / "kinematic_scorecard.json").exists())
            self.assertTrue((root / "out" / "scorecard_report.json").exists())


if __name__ == "__main__":
    unittest.main()
