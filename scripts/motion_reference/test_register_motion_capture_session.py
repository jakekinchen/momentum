#!/usr/bin/env python3
"""Unit coverage for motion capture session registration."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from register_motion_capture_session import SourceInput, register_capture_session


class RegisterMotionCaptureSessionTests(unittest.TestCase):
    def test_registers_sources_and_writes_manifest_patch_without_promotion(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            source = tmp_dir / "plank-side.mp4"
            source.write_bytes(b"fake source bytes")

            report = register_capture_session(
                exercise_id="bodyweight_plank",
                session_id="test_session",
                sources=[SourceInput(view="side", path=source)],
                output_root=tmp_dir / "dist" / "motion-reference",
                source_kind="first_party_trainer_capture",
                camera_view="side",
                fps=60,
                resolution={"width": 1920, "height": 1080},
                equipment="mat",
                license_name="First-party CamiFit trainer capture",
                performer_notes="test performer",
                reviewer_notes="two clean reps",
            )

            capture_path = Path(report["capture_session_path"])
            visual_review_path = Path(report["visual_review_path"])
            self.assertTrue(capture_path.exists())
            self.assertTrue(visual_review_path.exists())

            capture_session = json.loads(capture_path.read_text(encoding="utf-8"))
            visual_review = json.loads(visual_review_path.read_text(encoding="utf-8"))
            self.assertEqual(capture_session["exercise_id"], "bodyweight_plank")
            self.assertEqual(capture_session["source_files"][0]["bytes"], len(b"fake source bytes"))
            self.assertEqual(visual_review["status"], "pending")
            self.assertEqual(report["promotion_state"], "not_promoted")
            self.assertIn("capture_session_path", report["manifest_patch"])
            self.assertIn("visual_review_path", report["manifest_patch"])

    def test_rejects_invalid_exercise_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "source.mp4"
            source.write_bytes(b"x")

            with self.assertRaises(ValueError):
                register_capture_session(
                    exercise_id="../plank",
                    session_id="test_session",
                    sources=[SourceInput(view="side", path=source)],
                    output_root=Path(tmp) / "out",
                    source_kind="first_party_trainer_capture",
                    camera_view="side",
                    fps=60,
                    resolution="1920x1080",
                    equipment="mat",
                    license_name="First-party CamiFit trainer capture",
                    performer_notes="",
                    reviewer_notes="",
                )


if __name__ == "__main__":
    unittest.main()
