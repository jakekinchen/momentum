#!/usr/bin/env python3
"""Unit coverage for the motion pipeline gap report classifier."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

import report_motion_pipeline_gaps as report  # noqa: E402


class MotionPipelineGapReportTests(unittest.TestCase):
    def test_accepted_reference_with_manifest_failures_needs_provenance_backfill(self) -> None:
        status = report.classify_reference_status(
            profile={"capture": {"status": "first_party_webcam_reference"}},
            demo_exists=True,
            demo_ok=True,
            manifest={"exercise_id": "bodyweight_pushup"},
            acceptance_failures=["missing_reference_artifact:raw_trace=dist/example/raw.jsonl"],
            pending_failures=[],
        )

        self.assertEqual(status, "accepted_reference_missing_provenance")

    def test_blocked_visual_rig_review_stays_blocked(self) -> None:
        status = report.classify_reference_status(
            profile={
                "viewer_status": "pending_reference_capture",
                "capture": {"status": "pending_visual_rig_review"},
                "normalizer": {"status": "blocked_visual_rig_review_failed"},
            },
            demo_exists=False,
            demo_ok=False,
            manifest=None,
            acceptance_failures=[],
            pending_failures=[],
        )

        self.assertEqual(status, "blocked_visual_review")

    def test_local_only_guide_ready_row_gets_storage_action(self) -> None:
        action = report.next_action_for_row(
            {
                "exercise_id": "bodyweight_squat",
                "reference_status": "provenance_complete_guide_ready",
                "gate_status": "guide_ready",
                "playable_jsonl": True,
                "local_only_artifacts": ["dist/motion-reference/bodyweight_squat/raw.jsonl"],
            }
        )

        self.assertIn("durable artifact store", action)

    def test_compact_reason_keeps_report_readable(self) -> None:
        self.assertEqual(
            report.compact_reason("missing_reference_artifact:raw_trace=dist/example/raw.jsonl"),
            "missing artifact: raw_trace=dist/example/raw.jsonl",
        )


if __name__ == "__main__":
    unittest.main()
