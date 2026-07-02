#!/usr/bin/env python3
"""Unit coverage for motion provenance audit helpers."""

from __future__ import annotations

import copy
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from scripts.motion_reference import audit_motion_coverage as audit  # noqa: E402


def artifact_integrity(path: str) -> dict[str, object]:
    artifact = REPO_ROOT / path
    digest = hashlib.sha256()
    with artifact.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return {
        "bytes": artifact.stat().st_size,
        "sha256": digest.hexdigest(),
    }


def live_app_review(exercise_id: str) -> dict[str, object]:
    return {
        "status": "passed",
        "evidence": "Unit-test installed app review evidence.",
        "app_bundle": "/Applications/Momentum.app",
        "installed_playable_jsonls": 1,
        "installed_playable_trace_ids": [exercise_id],
    }


class ReferenceAcceptanceManifestTests(unittest.TestCase):
    def test_first_party_reference_requires_source_preserving_manifest(self) -> None:
        profile = {
            "capture": {"status": "first_party_webcam_reference"},
            "qa_gates": ["viewer_reviewed", "engine_counts_one_rep"],
        }
        manifest = {
            "source_kind": "trainer_reference_trace",
            "source_label": "first-party capture",
            "source_video": "dist/motion-reference/bodyweight_pushup/user_capture_20260606-005504/bodyweight_pushup_reference.mov",
            "raw_trace": "dist/motion-reference/bodyweight_pushup/user_capture_20260606-005504/raw_mediapipe.jsonl",
            "normalizer": "scripts/motion_reference/normalize_pushup_trace.py",
            "output_trace": "dist/motion-reference/bodyweight_pushup/user_capture_20260606-005504/bodyweight_pushup.normalized.jsonl",
        }

        failures = audit.manifest_reference_acceptance_failures(profile, manifest)

        self.assertIn("playable_trace_not_explicitly_packaged", failures)
        self.assertIn("missing_reference_metadata:acceptance_status", failures)
        self.assertIn("missing_reference_metadata:source_license", failures)
        self.assertIn("missing_reference_metadata:source_attribution", failures)
        self.assertIn("missing_reference_metadata:golden_comparison", failures)
        self.assertIn("missing_reference_metadata:visual_review", failures)
        self.assertIn("missing_reference_metadata:engine_replay", failures)
        self.assertIn("missing_reference_metadata:live_app_review", failures)

    def test_first_party_reference_accepts_complete_source_preserving_manifest(self) -> None:
        profile = {
            "capture": {"status": "first_party_webcam_reference"},
            "qa_gates": ["viewer_reviewed", "engine_counts_one_rep"],
        }
        manifest = {
            "exercise_id": "bodyweight_pushup",
            "acceptance_status": "accepted_source_preserving_reference",
            "playable_trace_packaged": True,
            "source_kind": "trainer_reference_trace",
            "source_label": "first-party capture",
            "source_video": "dist/motion-reference/bodyweight_pushup/user_capture_20260606-005504/bodyweight_pushup_reference.mov",
            "source_license": "First-party CamiFit user capture",
            "source_attribution": "CamiFit first-party webcam capture user_capture_20260606-005504",
            "raw_trace": "dist/motion-reference/bodyweight_pushup/user_capture_20260606-005504/raw_mediapipe.jsonl",
            "normalizer": "scripts/motion_reference/normalize_pushup_trace.py",
            "output_trace": "dist/motion-reference/bodyweight_pushup/user_capture_20260606-005504/bodyweight_pushup.normalized.jsonl",
            "golden_comparison": {
                "status": "not_applicable",
                "reason": "No protected push-up family comparator exists yet.",
            },
            "visual_review": {
                "status": "passed",
                "evidence": "App avatar review passed for the promoted first-party push-up trace.",
            },
            "engine_replay": {
                "status": "passed",
                "test": "MediaPipePoseProviderTests/testGuideReadyMotionDemoTracesDecodeAndReplayThroughEngine",
                "actual_final_reps": 1,
            },
            "live_app_review": live_app_review("bodyweight_pushup"),
            "artifact_integrity": {
                "source_video": artifact_integrity("dist/motion-reference/bodyweight_pushup/user_capture_20260606-005504/bodyweight_pushup_reference.mov"),
                "raw_trace": artifact_integrity("dist/motion-reference/bodyweight_pushup/user_capture_20260606-005504/raw_mediapipe.jsonl"),
                "normalizer": artifact_integrity("scripts/motion_reference/normalize_pushup_trace.py"),
                "output_trace": artifact_integrity("dist/motion-reference/bodyweight_pushup/user_capture_20260606-005504/bodyweight_pushup.normalized.jsonl"),
            },
        }

        self.assertEqual(audit.manifest_reference_acceptance_failures(profile, manifest), [])

    def test_review_only_manifest_is_not_promoted(self) -> None:
        manifest = {
            "exercise_id": "bodyweight_pike",
            "playable_trace_packaged": True,
            "acceptance_status": "blocked_visual_rig_review_failed",
            "packaging_scope": "motion_review_gallery_demo_only",
        }
        self.assertTrue(audit.is_review_only_manifest(manifest))
        self.assertFalse(audit.promoted_manifest(manifest))

    def test_review_only_scope_cannot_carry_accepted_status(self) -> None:
        manifest = {
            "exercise_id": "bodyweight_pike",
            "playable_trace_packaged": True,
            "acceptance_status": "accepted_source_preserving_reference",
            "packaging_scope": "motion_review_gallery_demo_only",
        }
        self.assertFalse(audit.is_review_only_manifest(manifest))
        self.assertTrue(audit.promoted_manifest(manifest))

    def test_review_only_playable_allowed_without_preset_but_needs_integrity(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            motion_demos = Path(directory)
            trace = motion_demos / "bodyweight_jumping_jack.jsonl"
            trace.write_text("{}\n", encoding="utf-8")
            manifest = {
                "exercise_id": "bodyweight_jumping_jack",
                "playable_trace_packaged": True,
                "acceptance_status": "pending_reference_capture",
                "packaging_scope": "motion_review_gallery_demo_only",
                "output_trace": str(trace),
            }
            (motion_demos / "bodyweight_jumping_jack.manifest.json").write_text(
                json.dumps(manifest), encoding="utf-8"
            )

            failures = audit.motion_demo_inventory_failures(
                motion_demos,
                presets={},
                profiles={"bodyweight_jumping_jack": {}},
            )

        self.assertNotIn(
            "bodyweight_jumping_jack: playable demo trace has no packaged preset", failures
        )
        self.assertIn(
            "bodyweight_jumping_jack: missing_reference_metadata:artifact_integrity", failures
        )

    def test_authored_keypose_capture_status_is_accepted(self) -> None:
        profile = {"capture": {"status": "first_party_authored_keyposes"}}
        self.assertTrue(audit.has_accepted_reference_clip(profile))

    def authored_profile(self) -> dict[str, object]:
        return {
            "exercise_id": "standing_miniband_hip_flexion",
            "viewer_status": "bundled_canonical_trace",
            "capture": {"status": "first_party_authored_keyposes"},
            "qa_gates": ["viewer_reviewed", "engine_counts_one_rep"],
        }

    def authored_manifest(self) -> dict[str, object]:
        normalizer = "scripts/motion_reference/compile_archetype_trace.py"
        output_trace = "Sources/CamiFitApp/Resources/MotionDemos/standing_miniband_hip_flexion.jsonl"
        return {
            "exercise_id": "standing_miniband_hip_flexion",
            "source_kind": "canonical_archetype_authored",
            "source_label": "standing_hip_flexion first-party authored keyposes",
            "acceptance_status": "accepted_authored_canonical_reference",
            "playable_trace_packaged": True,
            "source_license": "First-party authored keyposes; no external motion data.",
            "source_attribution": "CamiFit motion team authored keypose timeline",
            "normalizer": normalizer,
            "output_trace": output_trace,
            "golden_comparison": {
                "status": "not_applicable",
                "reason": "Authored canonical trace; no golden comparator applies.",
            },
            "visual_review": {"status": "passed", "evidence": "Unit-test visual review evidence."},
            "engine_replay": {
                "status": "passed",
                "test": "MediaPipePoseProviderTests/testGuideReadyMotionDemoTracesDecodeAndReplayThroughEngine",
                "actual_final_reps": 1,
            },
            "live_app_review": live_app_review("standing_miniband_hip_flexion"),
            "artifact_integrity": {
                "normalizer": artifact_integrity(normalizer),
                "output_trace": artifact_integrity(output_trace),
            },
        }

    def test_authored_reference_accepts_complete_manifest(self) -> None:
        failures = audit.manifest_reference_acceptance_failures(
            self.authored_profile(), self.authored_manifest()
        )
        self.assertEqual(failures, [])

    def test_authored_reference_rejects_unexpected_source_kind(self) -> None:
        manifest = self.authored_manifest()
        manifest["source_kind"] = "canonical_archetype_trace"
        failures = audit.manifest_reference_acceptance_failures(self.authored_profile(), manifest)
        self.assertIn("unexpected_reference_source_kind:canonical_archetype_trace", failures)

    def test_authored_reference_requires_output_trace_path(self) -> None:
        manifest = self.authored_manifest()
        manifest.pop("output_trace")
        failures = audit.manifest_reference_acceptance_failures(self.authored_profile(), manifest)
        self.assertIn("missing_reference_path:output_trace", failures)

    def test_accepted_reference_requires_golden_comparison_decision(self) -> None:
        profile = {
            "capture": {"status": "licensed_external_reference_clip"},
            "qa_gates": ["raw_pose_reviewed", "viewer_reviewed", "engine_counts_one_rep"],
        }
        manifest = {
            "exercise_id": "bodyweight_plank",
            "acceptance_status": "accepted_source_preserving_reference",
            "playable_trace_packaged": True,
            "source_kind": "licensed_external_reference_trace",
            "source_label": "licensed source",
            "source_page": "https://example.invalid/source",
            "source_media_url": "https://example.invalid/source.mp4",
            "source_video": "dist/motion-reference/bodyweight_plank/source/a-woman-doing-plank-exercise-on-a-yoga-mat-7801720.mp4",
            "source_license": "Pexels License",
            "source_attribution": "Pexels",
            "raw_trace": "dist/motion-reference/bodyweight_plank/pexels_plank_7801720_0_6/raw_mediapipe.jsonl",
            "normalizer": "scripts/motion_reference/normalize_plank_trace.py",
            "output_trace": "dist/motion-reference/bodyweight_plank/pexels_plank_7801720_0_6/bodyweight_plank.static_median.jsonl",
        }

        missing_failures = audit.manifest_reference_acceptance_failures(profile, manifest)
        manifest["golden_comparison"] = {
            "status": "not_applicable",
            "reason": "No protected plank comparator exists yet.",
        }
        manifest["visual_review"] = {
            "status": "passed",
            "evidence": "App avatar review passed for the promoted plank trace.",
        }
        manifest["engine_replay"] = {
            "status": "passed",
            "test": "MediaPipePoseProviderTests/testGuideReadyMotionDemoTracesDecodeAndReplayThroughEngine",
            "actual_hold_target_reached": True,
        }
        manifest["live_app_review"] = live_app_review("bodyweight_plank")
        manifest["artifact_integrity"] = {
            "source_video": artifact_integrity("dist/motion-reference/bodyweight_plank/source/a-woman-doing-plank-exercise-on-a-yoga-mat-7801720.mp4"),
            "raw_trace": artifact_integrity("dist/motion-reference/bodyweight_plank/pexels_plank_7801720_0_6/raw_mediapipe.jsonl"),
            "normalizer": artifact_integrity("scripts/motion_reference/normalize_plank_trace.py"),
            "output_trace": artifact_integrity("dist/motion-reference/bodyweight_plank/pexels_plank_7801720_0_6/bodyweight_plank.static_median.jsonl"),
        }
        manifest["rejected_sources"] = {
            "status": "none_retained_for_promotion_review",
            "review_scope": "Unit-test promotion scope: no alternate source candidates retained.",
            "reason": "The accepted source is pinned by source, license, raw trace, normalizer, replay, visual review, and artifact integrity.",
        }

        self.assertIn("missing_reference_metadata:golden_comparison", missing_failures)
        self.assertIn("missing_reference_metadata:rejected_sources_or_rejected_candidates", missing_failures)
        self.assertEqual(audit.manifest_reference_acceptance_failures(profile, manifest), [])

    def test_licensed_external_reference_rejects_malformed_rejected_candidate(self) -> None:
        profile = {
            "capture": {"status": "licensed_external_reference_clip"},
            "qa_gates": ["raw_pose_reviewed", "viewer_reviewed", "engine_counts_one_rep"],
        }
        manifest = {
            "exercise_id": "bodyweight_plank",
            "acceptance_status": "accepted_source_preserving_reference",
            "playable_trace_packaged": True,
            "source_kind": "licensed_external_reference_trace",
            "source_label": "licensed source",
            "source_page": "https://example.invalid/source",
            "source_media_url": "https://example.invalid/source.mp4",
            "source_video": "dist/motion-reference/bodyweight_plank/source/a-woman-doing-plank-exercise-on-a-yoga-mat-7801720.mp4",
            "source_license": "Pexels License",
            "source_attribution": "Pexels",
            "raw_trace": "dist/motion-reference/bodyweight_plank/pexels_plank_7801720_0_6/raw_mediapipe.jsonl",
            "normalizer": "scripts/motion_reference/normalize_plank_trace.py",
            "output_trace": "dist/motion-reference/bodyweight_plank/pexels_plank_7801720_0_6/bodyweight_plank.static_median.jsonl",
            "golden_comparison": {
                "status": "not_applicable",
                "reason": "No protected plank comparator exists yet.",
            },
            "visual_review": {
                "status": "passed",
                "evidence": "App avatar review passed for the promoted plank trace.",
            },
            "engine_replay": {
                "status": "passed",
                "test": "MediaPipePoseProviderTests/testGuideReadyMotionDemoTracesDecodeAndReplayThroughEngine",
                "actual_hold_target_reached": True,
            },
            "live_app_review": live_app_review("bodyweight_plank"),
            "artifact_integrity": {
                "source_video": artifact_integrity("dist/motion-reference/bodyweight_plank/source/a-woman-doing-plank-exercise-on-a-yoga-mat-7801720.mp4"),
                "raw_trace": artifact_integrity("dist/motion-reference/bodyweight_plank/pexels_plank_7801720_0_6/raw_mediapipe.jsonl"),
                "normalizer": artifact_integrity("scripts/motion_reference/normalize_plank_trace.py"),
                "output_trace": artifact_integrity("dist/motion-reference/bodyweight_plank/pexels_plank_7801720_0_6/bodyweight_plank.static_median.jsonl"),
            },
            "rejected_candidates": [
                {
                    "source_license": "Pexels License",
                    "source_attribution": "Pexels",
                    "decision": "accepted",
                    "reason": "This malformed record is intentionally not a rejection.",
                }
            ],
        }

        failures = audit.manifest_reference_acceptance_failures(profile, manifest)

        self.assertIn("missing_reference_metadata:rejected_candidates[0]:missing_source", failures)
        self.assertIn("missing_reference_metadata:rejected_candidates[0]:decision_not_rejected", failures)

    def test_licensed_external_reference_accepts_rejected_candidate_list(self) -> None:
        profile = {
            "capture": {"status": "licensed_external_reference_clip"},
            "qa_gates": ["raw_pose_reviewed", "viewer_reviewed", "engine_counts_one_rep"],
        }
        manifest = {
            "exercise_id": "bodyweight_plank",
            "acceptance_status": "accepted_source_preserving_reference",
            "playable_trace_packaged": True,
            "source_kind": "licensed_external_reference_trace",
            "source_label": "licensed source",
            "source_page": "https://example.invalid/source",
            "source_media_url": "https://example.invalid/source.mp4",
            "source_video": "dist/motion-reference/bodyweight_plank/source/a-woman-doing-plank-exercise-on-a-yoga-mat-7801720.mp4",
            "source_license": "Pexels License",
            "source_attribution": "Pexels",
            "raw_trace": "dist/motion-reference/bodyweight_plank/pexels_plank_7801720_0_6/raw_mediapipe.jsonl",
            "normalizer": "scripts/motion_reference/normalize_plank_trace.py",
            "output_trace": "dist/motion-reference/bodyweight_plank/pexels_plank_7801720_0_6/bodyweight_plank.static_median.jsonl",
            "golden_comparison": {
                "status": "not_applicable",
                "reason": "No protected plank comparator exists yet.",
            },
            "visual_review": {
                "status": "passed",
                "evidence": "App avatar review passed for the promoted plank trace.",
            },
            "engine_replay": {
                "status": "passed",
                "test": "MediaPipePoseProviderTests/testGuideReadyMotionDemoTracesDecodeAndReplayThroughEngine",
                "actual_hold_target_reached": True,
            },
            "live_app_review": live_app_review("bodyweight_plank"),
            "artifact_integrity": {
                "source_video": artifact_integrity("dist/motion-reference/bodyweight_plank/source/a-woman-doing-plank-exercise-on-a-yoga-mat-7801720.mp4"),
                "raw_trace": artifact_integrity("dist/motion-reference/bodyweight_plank/pexels_plank_7801720_0_6/raw_mediapipe.jsonl"),
                "normalizer": artifact_integrity("scripts/motion_reference/normalize_plank_trace.py"),
                "output_trace": artifact_integrity("dist/motion-reference/bodyweight_plank/pexels_plank_7801720_0_6/bodyweight_plank.static_median.jsonl"),
            },
            "rejected_candidates": [
                {
                    "source_page": "https://example.invalid/rejected",
                    "source_license": "Pexels License",
                    "source_attribution": "Pexels rejected clip",
                    "decision": "rejected",
                    "reason": "The source did not preserve the required pose-visible motion.",
                }
            ],
        }

        self.assertEqual(audit.manifest_reference_acceptance_failures(profile, manifest), [])

    def test_pending_reference_capture_requires_source_search_record(self) -> None:
        profile = {
            "exercise_id": "bodyweight_pike",
            "viewer_status": "pending_reference_capture",
            "capture": {"status": "pending_visual_rig_review"},
        }

        failures = audit.pending_source_search_failures(profile)

        self.assertIn("pending_source_search:rejected_sources_or_rejected_candidates", failures)

    def test_pending_reference_capture_accepts_rejected_candidate_record(self) -> None:
        profile = {
            "exercise_id": "bodyweight_pike",
            "viewer_status": "pending_reference_capture",
            "capture": {
                "status": "pending_visual_rig_review",
                "rejected_candidates": [
                    {
                        "source_page": "https://example.invalid/pike",
                        "source_media_url": "https://example.invalid/pike.mp4",
                        "source_license": "Pexels License",
                        "source_attribution": "Pexels rejected pike candidate",
                        "decision": "rejected - visual rig review failed",
                        "reason": "Fixed-frame app review showed detached head/neck deformation.",
                    }
                ],
            },
        }

        self.assertEqual(audit.pending_source_search_failures(profile), [])

    def test_strict_inventory_checks_profile_only_pending_source_search(self) -> None:
        profile = {
            "exercise_id": "bodyweight_jumping_jack",
            "viewer_status": "pending_reference_capture",
            "capture": {"status": "pending_licensed_reference_clip"},
        }

        with tempfile.TemporaryDirectory() as directory:
            failures = audit.strict_fail_closed_inventory_failures(
                Path(directory),
                presets={},
                profiles={"bodyweight_jumping_jack": profile},
            )

        self.assertIn(
            "bodyweight_jumping_jack: pending_source_search:rejected_sources_or_rejected_candidates",
            failures,
        )

    def test_strict_inventory_rejects_pending_playable_demo_trace(self) -> None:
        profile = {
            "exercise_id": "bodyweight_pike",
            "viewer_status": "pending_reference_capture",
            "capture": {
                "status": "pending_visual_rig_review",
                "rejected_candidates": [
                    {
                        "source_page": "https://example.invalid/pike",
                        "source_media_url": "https://example.invalid/pike.mp4",
                        "source_license": "Pexels License",
                        "source_attribution": "Pexels rejected pike candidate",
                        "decision": "rejected - visual rig review failed",
                        "reason": "Fixed-frame app review showed detached head/neck deformation.",
                    }
                ],
            },
        }

        with tempfile.TemporaryDirectory() as directory:
            motion_demos = Path(directory)
            (motion_demos / "bodyweight_pike.jsonl").write_text("{}\n", encoding="utf-8")
            failures = audit.strict_fail_closed_inventory_failures(
                motion_demos,
                presets={"bodyweight_pike": {}},
                profiles={"bodyweight_pike": profile},
            )

        self.assertTrue(
            any(failure.startswith("bodyweight_pike: pending reference capture must not ship playable demo trace") for failure in failures),
            failures,
        )

    def test_protected_golden_requires_golden_and_candidate_trace_paths(self) -> None:
        profile = {
            "exercise_id": "bodyweight_lunge",
            "validation_role": "protected_golden_comparator",
            "capture": {"status": "protected_golden_reference"},
            "qa_gates": ["viewer_reviewed", "engine_counts_one_rep"],
        }
        manifest = {
            "acceptance_status": "protected_golden_loop_closed",
            "playable_trace_packaged": True,
            "source_kind": "trainer_reference_video",
            "source_label": "Wikimedia Commons Strength Training Circuit - Forward Lunge",
            "source_url": "https://commons.wikimedia.org/wiki/File:Strength_Training_Circuit-_Forward_Lunge.webm",
            "source_media_url": "https://upload.wikimedia.org/wikipedia/commons/5/57/Strength_Training_Circuit-_Forward_Lunge.webm",
            "source_video": "dist/motion-reference/bodyweight_lunge/source/commons-forward-lunge.webm",
            "source_license": "Public domain (U.S. Army / U.S. federal government work)",
            "source_attribution": "Army Combat Fitness Test / U.S. Army via Wikimedia Commons",
            "raw_trace": "dist/motion-reference/bodyweight_lunge/commons_forward_lunge_30_36/raw_mediapipe.jsonl",
            "normalizer": "scripts/motion_reference/normalize_lunge_trace.py",
            "output_trace": "dist/motion-reference/bodyweight_lunge/commons_forward_lunge_30_36/bodyweight_lunge.jsonl",
            "candidate_trace": "dist/motion-reference/bodyweight_lunge/commons_forward_lunge_30_36/bodyweight_lunge.raw_preserved.jsonl",
            "golden_trace": "Sources/CamiFitApp/Resources/MotionDemos/bodyweight_lunge.jsonl",
            "golden_comparison": {
                "status": "reviewed",
                "golden_trace": "Sources/CamiFitApp/Resources/MotionDemos/bodyweight_lunge.jsonl",
                "candidate_trace": "dist/motion-reference/bodyweight_lunge/commons_forward_lunge_30_36/bodyweight_lunge.raw_preserved.jsonl",
                "comparison_report": "dist/motion-reference/bodyweight_lunge/commons_forward_lunge_30_36/golden_comparison.json",
            },
            "visual_review": {
                "status": "passed",
                "evidence": "App avatar review passed for the protected lunge trace.",
            },
            "engine_replay": {
                "status": "passed",
                "test": "MediaPipePoseProviderTests/testGuideReadyMotionDemoTracesDecodeAndReplayThroughEngine",
                "actual_final_reps": 1,
            },
            "live_app_review": live_app_review("bodyweight_lunge"),
            "artifact_integrity": {
                "source_video": artifact_integrity("dist/motion-reference/bodyweight_lunge/source/commons-forward-lunge.webm"),
                "raw_trace": artifact_integrity("dist/motion-reference/bodyweight_lunge/commons_forward_lunge_30_36/raw_mediapipe.jsonl"),
                "normalizer": artifact_integrity("scripts/motion_reference/normalize_lunge_trace.py"),
                "output_trace": artifact_integrity("dist/motion-reference/bodyweight_lunge/commons_forward_lunge_30_36/bodyweight_lunge.jsonl"),
                "golden_trace": artifact_integrity("Sources/CamiFitApp/Resources/MotionDemos/bodyweight_lunge.jsonl"),
                "candidate_trace": artifact_integrity("dist/motion-reference/bodyweight_lunge/commons_forward_lunge_30_36/bodyweight_lunge.raw_preserved.jsonl"),
                "golden_comparison.golden_trace": artifact_integrity("Sources/CamiFitApp/Resources/MotionDemos/bodyweight_lunge.jsonl"),
                "golden_comparison.candidate_trace": artifact_integrity("dist/motion-reference/bodyweight_lunge/commons_forward_lunge_30_36/bodyweight_lunge.raw_preserved.jsonl"),
                "golden_comparison.comparison_report": artifact_integrity("dist/motion-reference/bodyweight_lunge/commons_forward_lunge_30_36/golden_comparison.json"),
            },
        }

        complete_failures = audit.manifest_reference_acceptance_failures(profile, manifest)
        missing_golden_manifest = copy.deepcopy(manifest)
        del missing_golden_manifest["golden_trace"]
        missing_comparison_manifest = copy.deepcopy(manifest)
        del missing_comparison_manifest["golden_comparison"]
        candidate_as_golden_manifest = copy.deepcopy(manifest)
        candidate_as_golden_manifest["golden_trace"] = candidate_as_golden_manifest["candidate_trace"]
        candidate_as_golden_manifest["golden_comparison"]["golden_trace"] = candidate_as_golden_manifest["candidate_trace"]
        candidate_as_golden_manifest["artifact_integrity"]["golden_trace"] = artifact_integrity(
            "dist/motion-reference/bodyweight_lunge/commons_forward_lunge_30_36/bodyweight_lunge.raw_preserved.jsonl"
        )
        candidate_as_golden_manifest["artifact_integrity"]["golden_comparison.golden_trace"] = artifact_integrity(
            "dist/motion-reference/bodyweight_lunge/commons_forward_lunge_30_36/bodyweight_lunge.raw_preserved.jsonl"
        )
        missing_failures = audit.manifest_reference_acceptance_failures(profile, missing_golden_manifest)
        missing_comparison_failures = audit.manifest_reference_acceptance_failures(profile, missing_comparison_manifest)
        candidate_as_golden_failures = audit.manifest_reference_acceptance_failures(
            profile,
            candidate_as_golden_manifest,
        )

        self.assertEqual(complete_failures, [])
        self.assertIn("missing_reference_path:golden_trace", missing_failures)
        self.assertIn("missing_reference_metadata:golden_comparison", missing_comparison_failures)
        self.assertIn("protected_golden_sha256_mismatch:bodyweight_lunge", candidate_as_golden_failures)

    def test_accepted_reference_rejects_artifact_hash_mismatch(self) -> None:
        profile = {
            "capture": {"status": "first_party_webcam_reference"},
            "qa_gates": ["viewer_reviewed", "engine_counts_one_rep"],
        }
        source_video = "dist/motion-reference/bodyweight_pushup/user_capture_20260606-005504/bodyweight_pushup_reference.mov"
        manifest = {
            "exercise_id": "bodyweight_pushup",
            "acceptance_status": "accepted_source_preserving_reference",
            "playable_trace_packaged": True,
            "source_kind": "trainer_reference_trace",
            "source_label": "first-party capture",
            "source_video": source_video,
            "source_license": "First-party CamiFit user capture",
            "source_attribution": "CamiFit first-party webcam capture user_capture_20260606-005504",
            "raw_trace": "dist/motion-reference/bodyweight_pushup/user_capture_20260606-005504/raw_mediapipe.jsonl",
            "normalizer": "scripts/motion_reference/normalize_pushup_trace.py",
            "output_trace": "dist/motion-reference/bodyweight_pushup/user_capture_20260606-005504/bodyweight_pushup.normalized.jsonl",
            "golden_comparison": {
                "status": "not_applicable",
                "reason": "No protected push-up family comparator exists yet.",
            },
            "visual_review": {
                "status": "passed",
                "evidence": "App avatar review passed for the promoted first-party push-up trace.",
            },
            "engine_replay": {
                "status": "passed",
                "test": "MediaPipePoseProviderTests/testGuideReadyMotionDemoTracesDecodeAndReplayThroughEngine",
                "actual_final_reps": 1,
            },
            "live_app_review": live_app_review("bodyweight_pushup"),
            "artifact_integrity": {
                "source_video": {
                    **artifact_integrity(source_video),
                    "sha256": "0" * 64,
                },
                "raw_trace": artifact_integrity("dist/motion-reference/bodyweight_pushup/user_capture_20260606-005504/raw_mediapipe.jsonl"),
                "normalizer": artifact_integrity("scripts/motion_reference/normalize_pushup_trace.py"),
                "output_trace": artifact_integrity("dist/motion-reference/bodyweight_pushup/user_capture_20260606-005504/bodyweight_pushup.normalized.jsonl"),
            },
        }

        failures = audit.manifest_reference_acceptance_failures(profile, manifest)

        self.assertIn("artifact_sha256_mismatch:source_video", failures)

    def test_motion_demo_inventory_rejects_orphan_playable_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            motion_demos = Path(directory)
            (motion_demos / "known.jsonl").write_text("{}\n", encoding="utf-8")
            (motion_demos / "orphan.jsonl").write_text("{}\n", encoding="utf-8")
            (motion_demos / "promoted_without_trace.manifest.json").write_text(
                json.dumps({
                    "exercise_id": "promoted_without_trace",
                    "acceptance_status": "accepted_source_preserving_reference",
                    "playable_trace_packaged": True,
                }),
                encoding="utf-8",
            )
            artifact = motion_demos / "source_artifact.bin"
            artifact.write_text("source artifact", encoding="utf-8")
            (motion_demos / "promoted_with_unpinned_artifacts.jsonl").write_text("{}\n", encoding="utf-8")
            (motion_demos / "promoted_with_unpinned_artifacts.manifest.json").write_text(
                json.dumps({
                    "exercise_id": "promoted_with_unpinned_artifacts",
                    "acceptance_status": "accepted_source_preserving_reference",
                    "playable_trace_packaged": True,
                    "source_video": str(artifact),
                    "raw_trace": str(artifact),
                    "normalizer": str(artifact),
                    "output_trace": str(artifact),
                }),
                encoding="utf-8",
            )

            failures = audit.motion_demo_inventory_failures(
                motion_demos,
                presets={
                    "known": {},
                    "promoted_without_trace": {},
                    "promoted_with_unpinned_artifacts": {},
                },
                profiles={
                    "known": {},
                    "promoted_without_trace": {},
                    "promoted_with_unpinned_artifacts": {},
                },
            )

        self.assertIn("orphan: playable demo trace has no packaged preset", failures)
        self.assertIn("orphan: playable demo trace has no motion profile", failures)
        self.assertIn("promoted_without_trace: promoted manifest has no playable demo trace", failures)
        self.assertIn(
            "promoted_with_unpinned_artifacts: missing_reference_metadata:artifact_integrity",
            failures,
        )

    def test_swift_tracking_gate_parser_reads_string_sets(self) -> None:
        source = """
        enum AppExerciseTrackingGate {
            static let guideReadyPresetIDs: Set<String> = [
                "bodyweight_lunge",
                "bodyweight_squat"
            ]

            static let referenceCaptureRequiredPresetIDs: Set<String> = [
                "bodyweight_pike"
            ]
        }
        """

        self.assertEqual(
            audit.parse_swift_string_set(source, "guideReadyPresetIDs"),
            {"bodyweight_lunge", "bodyweight_squat"},
        )
        self.assertEqual(
            audit.parse_swift_string_set(source, "referenceCaptureRequiredPresetIDs"),
            {"bodyweight_pike"},
        )

    def test_guide_ready_inventory_enforces_exact_playable_set(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            motion_demos = Path(directory)
            (motion_demos / "extra.jsonl").write_text("{}\n", encoding="utf-8")
            (motion_demos / "pending.jsonl").write_text("{}\n", encoding="utf-8")

            failures = audit.guide_ready_inventory_failures(
                motion_demos,
                presets={},
                profiles={},
                guide_ready_ids={"missing"},
                reference_capture_ids={"pending"},
            )

        self.assertIn("extra: playable JSONL is not listed as guide-ready", failures)
        self.assertIn("pending: playable JSONL is not listed as guide-ready", failures)
        self.assertIn("pending: reference-capture preset must not ship playable JSONL", failures)
        self.assertIn("missing: guide-ready preset missing playable JSONL", failures)
        self.assertIn("missing: guide-ready preset missing packaged preset JSON", failures)
        self.assertIn("missing: guide-ready preset missing motion profile", failures)

    def test_guide_ready_inventory_requires_reference_gate_to_match_pending_profiles(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            motion_demos = Path(directory)
            (motion_demos / "ready.jsonl").write_text("{}\n", encoding="utf-8")
            (motion_demos / "ready.manifest.json").write_text(
                json.dumps({
                    "exercise_id": "ready",
                    "acceptance_status": "accepted_source_preserving_reference",
                    "playable_trace_packaged": True,
                    "live_app_review": {
                        "installed_playable_jsonls": 1,
                        "installed_playable_trace_ids": ["ready"],
                    },
                }),
                encoding="utf-8",
            )

            failures = audit.guide_ready_inventory_failures(
                motion_demos,
                presets={"ready": {}, "pending_a": {}},
                profiles={
                    "ready": {
                        "exercise_id": "ready",
                        "viewer_status": "trainer_reference_trace",
                        "capture": {"status": "first_party_webcam_reference"},
                    },
                    "pending_a": {
                        "exercise_id": "pending_a",
                        "viewer_status": "pending_reference_capture",
                        "capture": {"status": "pending_licensed_reference_clip"},
                    },
                    "pending_b": {
                        "exercise_id": "pending_b",
                        "viewer_status": "pending_reference_capture",
                        "capture": {"status": "pending_licensed_reference_clip"},
                    },
                },
                guide_ready_ids={"ready"},
                reference_capture_ids={"pending_a", "stale"},
            )

        self.assertIn("pending_b: pending profile is not listed as reference-capture-required", failures)
        self.assertIn("stale: reference-capture ID has no pending motion profile", failures)

    def test_guide_ready_inventory_rejects_stale_live_app_review_inventory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            motion_demos = Path(directory)
            (motion_demos / "ready.jsonl").write_text("{}\n", encoding="utf-8")
            (motion_demos / "ready.manifest.json").write_text(
                json.dumps({
                    "exercise_id": "ready",
                    "acceptance_status": "accepted_source_preserving_reference",
                    "playable_trace_packaged": True,
                    "live_app_review": {
                        "status": "passed",
                        "evidence": "stale installed-app inventory",
                        "app_bundle": "/Applications/Momentum.app",
                        "installed_playable_jsonls": 2,
                        "installed_playable_trace_ids": ["ready", "unexpected"],
                    },
                }),
                encoding="utf-8",
            )

            failures = audit.guide_ready_inventory_failures(
                motion_demos,
                presets={"ready": {}},
                profiles={
                    "ready": {
                        "exercise_id": "ready",
                        "viewer_status": "trainer_reference_trace",
                        "capture": {"status": "first_party_webcam_reference"},
                    }
                },
                guide_ready_ids={"ready"},
                reference_capture_ids=set(),
            )

        self.assertIn(
            "ready: guide-ready live_app_review installed_playable_jsonls=2 "
            "does not match packaged playable inventory 1",
            failures,
        )
        self.assertIn(
            "ready: guide-ready live_app_review installed_playable_trace_ids "
            "do not match packaged playable inventory",
            failures,
        )


if __name__ == "__main__":
    unittest.main()
