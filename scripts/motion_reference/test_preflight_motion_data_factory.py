#!/usr/bin/env python3
"""Unit coverage for the motion-data factory preflight classifier."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

import preflight_motion_data_factory as preflight  # noqa: E402


def base_row(**overrides: object) -> dict[str, object]:
    row: dict[str, object] = {
        "exercise_id": "bodyweight_squat",
        "label": "Bodyweight Squat",
        "motion_profile": True,
        "gate_status": "guide_ready",
        "playable_jsonl": True,
        "demo_status": "ok",
        "manifest_status": "accepted_source_preserving_reference",
        "reference_status": "accepted_reference_missing_provenance",
        "capture_status": "first_party_webcam_reference",
        "normalizer_status": "implemented",
        "local_only_artifacts": [],
        "missing": [],
        "next_action": "Backfill factory metadata.",
    }
    row.update(overrides)
    return row


def accepted_profile() -> dict[str, object]:
    return {
        "exercise_id": "bodyweight_squat",
        "viewer_status": "trainer_reference_trace",
        "capture": {"status": "first_party_webcam_reference"},
    }


def passed_visual_manifest(**overrides: object) -> dict[str, object]:
    manifest: dict[str, object] = {
        "exercise_id": "bodyweight_squat",
        "acceptance_status": "accepted_source_preserving_reference",
        "playable_trace_packaged": True,
        "visual_review": {
            "status": "passed",
            "evidence": "Human review passed.",
        },
    }
    manifest.update(overrides)
    return manifest


def validation_ready_manifest() -> dict[str, object]:
    return passed_visual_manifest(
        capture_session={
            "source_kind": "first_party_trainer_capture",
            "camera_view": "side",
            "fps": 60,
            "resolution": {"width": 1920, "height": 1080},
            "equipment": "none",
            "license": "First-party CamiFit capture",
            "reviewer_notes": "Two clean controlled reps.",
        },
        detector_agreement_scorecard={
            "status": "passed",
            "detectors": ["mediapipe", "movenet"],
            "metrics": {
                "frame_coverage": 1.0,
                "mean_visibility": 0.98,
                "detector_disagreement": 0.02,
                "identity_flip_count": 0,
                "temporal_jitter": 0.01,
                "rejected_frame_windows": [],
            },
        },
        kinematic_scorecard={
            "status": "passed",
            "metrics": {
                "limb_length_stability": 0.01,
                "joint_angle_limits": {},
                "smoothness_jerk": 0.02,
                "loop_boundary_delta": 0.0,
                "contact_lock_delta": 0.0,
                "phase_monotonicity": 1.0,
            },
        },
        runtime_validation_set={
            "status": "passed",
            "clip_count": 5,
        },
    )


class MotionDataFactoryPreflightTests(unittest.TestCase):
    def test_required_promotion_tiers_are_defined(self) -> None:
        self.assertEqual(
            preflight.PROMOTION_TIERS,
            (
                "recommendation-only",
                "source-candidate",
                "detector-reviewable",
                "avatar-demo-candidate",
                "guide-ready",
                "validation-ready",
            ),
        )

    def test_existing_guide_ready_can_remain_guide_ready_without_factory_scorecards(self) -> None:
        result = preflight.classify_factory_row(
            base_row(local_only_artifacts=["dist/motion-reference/bodyweight_squat/raw.jsonl"]),
            manifest=passed_visual_manifest(),
            profile=accepted_profile(),
        )

        self.assertEqual(result["promotion_tier"], "guide-ready")
        self.assertTrue(result["guide_ready"])
        self.assertFalse(result["validation_ready"])
        self.assertIn(
            "missing_detector_agreement_scorecard",
            result["machine_reasons"]["validation_ready_blockers"],
        )
        self.assertIn(
            "local_only_source_chain_artifacts",
            result["machine_reasons"]["validation_ready_blockers"],
        )

    def test_failed_visual_review_stays_below_guide_ready(self) -> None:
        manifest = passed_visual_manifest(
            acceptance_status="blocked_visual_rig_review_failed",
            playable_trace_packaged=False,
            output_trace="dist/motion-reference/bodyweight_plank/bodyweight_plank.jsonl",
            visual_review={
                "status": "failed",
                "evidence": "Avatar rig detached.",
            },
        )
        result = preflight.classify_factory_row(
            base_row(
                exercise_id="bodyweight_plank",
                label="Bodyweight Plank",
                gate_status="reference_capture_required",
                playable_jsonl=False,
                manifest_status="blocked_visual_rig_review_failed",
                capture_status="pending_licensed_reference_clip",
            ),
            manifest=manifest,
            profile={
                "exercise_id": "bodyweight_plank",
                "viewer_status": "pending_reference_capture",
                "capture": {"status": "pending_licensed_reference_clip"},
            },
        )

        self.assertEqual(result["promotion_tier"], "avatar-demo-candidate")
        self.assertFalse(result["guide_ready"])
        blockers = result["machine_reasons"]["guide_ready_blockers"]
        self.assertIn("reference_capture_required_gate", blockers)
        self.assertIn("visual_review_failed", blockers)

    def test_raw_detector_artifacts_classify_as_detector_reviewable(self) -> None:
        result = preflight.classify_factory_row(
            base_row(
                exercise_id="machine_chest_supported_row",
                label="Machine Chest-Supported Row",
                gate_status="reference_capture_required",
                playable_jsonl=False,
                manifest_status="pending_source_license_review",
                capture_status="pending_license_review",
            ),
            manifest={
                "exercise_id": "machine_chest_supported_row",
                "acceptance_status": "pending_source_license_review",
                "source_video": "dist/motion-reference/machine_chest_supported_row/source.webm",
                "raw_trace": "dist/motion-reference/machine_chest_supported_row/raw_mediapipe.jsonl",
            },
            profile={
                "exercise_id": "machine_chest_supported_row",
                "viewer_status": "pending_reference_capture",
                "capture": {"status": "pending_license_review"},
            },
        )

        self.assertEqual(result["promotion_tier"], "detector-reviewable")
        self.assertIn(
            "pending_source_license_review",
            result["machine_reasons"]["guide_ready_blockers"],
        )

    def test_full_factory_evidence_reaches_validation_ready(self) -> None:
        result = preflight.classify_factory_row(
            base_row(),
            manifest=validation_ready_manifest(),
            profile=accepted_profile(),
        )

        self.assertEqual(result["promotion_tier"], "validation-ready")
        self.assertTrue(result["guide_ready"])
        self.assertTrue(result["validation_ready"])
        self.assertEqual(result["machine_reasons"]["validation_ready_blockers"], [])

    def test_visual_review_path_counts_as_human_review_decision(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            review_path = Path(tmp) / "visual_review.json"
            review_path.write_text(
                json.dumps(
                    {
                        "status": "passed",
                        "evidence": "Side-by-side source, detector, and avatar review passed.",
                        "reviewer": "motion-qa",
                    }
                ),
                encoding="utf-8",
            )
            manifest = passed_visual_manifest(
                visual_review_path=str(review_path),
            )
            manifest.pop("visual_review")

            result = preflight.classify_factory_row(
                base_row(),
                manifest=manifest,
                profile=accepted_profile(),
            )

        self.assertTrue(result["guide_ready"])
        review = result["factory_concepts"]["human_visual_review_decision"]
        self.assertEqual(review["status"], "passed")
        self.assertEqual(review["reasons"], [])

    def test_current_inventory_preserves_guide_ready_and_blocks_capture_required(self) -> None:
        report = preflight.build_report(preflight.parse_args([]))
        self.assertEqual(report["summary"]["exercise_rows"], 15)

        guide_ready_ids = {
            row["exercise_id"]
            for row in report["exercises"]
            if row["promotion_tier"] in {"guide-ready", "validation-ready"}
        }
        self.assertEqual(
            guide_ready_ids,
            {
                "bodyweight_lunge",
                "bodyweight_pushup",
                "bodyweight_squat",
                "single_arm_cable_tricep_extension",
            },
        )
        for row in report["exercises"]:
            if row["current_signals"]["app_gate"] == "reference_capture_required":
                self.assertNotIn(row["promotion_tier"], {"guide-ready", "validation-ready"})
        self.assertEqual(report["summary"]["validation_ready"], 0)

    def test_schema_contract_files_are_valid_json_and_cover_factory_concepts(self) -> None:
        schema_dir = SCRIPT_DIR / "schemas"
        schemas = {
            path.name: json.loads(path.read_text(encoding="utf-8"))
            for path in schema_dir.glob("*.schema.json")
        }

        self.assertIn("capture_session.schema.json", schemas)
        self.assertIn("detector_agreement_scorecard.schema.json", schemas)
        self.assertIn("kinematic_scorecard.schema.json", schemas)
        self.assertIn("visual_review.schema.json", schemas)
        report_schema = schemas["motion_data_factory_preflight_report.schema.json"]
        exercise_concepts = (
            report_schema["properties"]["exercises"]["items"]["properties"]["factory_concepts"]["required"]
        )
        self.assertIn("capture_session_metadata", exercise_concepts)
        self.assertIn("detector_agreement_scorecard", exercise_concepts)
        self.assertIn("kinematic_scorecard", exercise_concepts)
        self.assertIn("human_visual_review_decision", exercise_concepts)

    def test_templates_are_valid_json_and_pin_next_capture_targets(self) -> None:
        template_dir = SCRIPT_DIR / "templates"
        templates = {
            path.name: json.loads(path.read_text(encoding="utf-8"))
            for path in template_dir.glob("*.json")
        }

        self.assertIn("capture_session.first_party_trainer.template.json", templates)
        self.assertIn("visual_review.template.json", templates)
        targets = templates["next_capture_targets.json"]["targets"]
        self.assertEqual(
            [target["exercise_id"] for target in targets],
            [
                "bodyweight_plank",
                "machine_chest_supported_row",
                "standing_miniband_hip_flexion",
            ],
        )


if __name__ == "__main__":
    unittest.main()
