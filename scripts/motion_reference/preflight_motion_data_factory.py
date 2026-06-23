#!/usr/bin/env python3
"""Preflight the CamiFit motion-data factory promotion tiers.

This command is intentionally stricter than the app inventory, but it does not
retroactively demote app-gated guide-ready exercises. Instead it separates the
current product tier from the factory evidence still needed before an exercise
can be called validation-ready.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import report_motion_pipeline_gaps
from audit_motion_coverage import (
    capture_status,
    load_manifest,
    load_profiles,
    repo_relative_path,
)


PROMOTION_TIERS = (
    "recommendation-only",
    "source-candidate",
    "detector-reviewable",
    "avatar-demo-candidate",
    "guide-ready",
    "validation-ready",
)
TIER_INDEX = {tier: index for index, tier in enumerate(PROMOTION_TIERS)}

PASSED_REVIEW_STATUSES = {"passed", "reviewed"}
PASSED_SCORECARD_STATUSES = {"passed", "reviewed"}

CAPTURE_SESSION_REQUIRED_FIELDS = (
    "source_kind",
    "camera_view",
    "fps",
    "resolution",
    "equipment",
    "license",
    "reviewer_notes",
)
DETECTOR_SCORECARD_REQUIRED_METRICS = (
    "frame_coverage",
    "mean_visibility",
    "detector_disagreement",
    "identity_flip_count",
    "temporal_jitter",
    "rejected_frame_windows",
)
KINEMATIC_SCORECARD_REQUIRED_METRICS = (
    "limb_length_stability",
    "joint_angle_limits",
    "smoothness_jerk",
    "loop_boundary_delta",
    "contact_lock_delta",
    "phase_monotonicity",
)


def non_empty_string(value: Any) -> str | None:
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None


def normalized_status(value: Any) -> str:
    if not isinstance(value, str):
        return ""
    return value.strip().lower()


def present_required_field(value: Any) -> bool:
    if isinstance(value, str):
        return bool(value.strip())
    return value is not None


def load_json_if_present(value: Any) -> tuple[dict[str, Any] | None, str | None]:
    path = repo_relative_path(value)
    if path is None:
        return None, "missing_path"
    if not path.exists():
        return None, f"missing_file:{value}"
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        return None, f"invalid_json:{value}:{error.lineno}"
    if not isinstance(payload, dict):
        return None, f"invalid_json_object:{value}"
    return payload, None


def capture_session_payload(manifest: dict[str, Any] | None) -> tuple[dict[str, Any] | None, list[str]]:
    if manifest is None:
        return None, ["missing_motion_manifest"]

    inline = manifest.get("capture_session")
    if isinstance(inline, dict):
        return inline, []

    for key in ("capture_session_path", "capture_session_file"):
        if key in manifest:
            payload, error = load_json_if_present(manifest.get(key))
            if payload is None:
                return None, [f"{key}:{error}"]
            return payload, []

    return None, ["missing_capture_session_metadata"]


def check_capture_session_metadata(manifest: dict[str, Any] | None) -> dict[str, Any]:
    payload, reasons = capture_session_payload(manifest)
    if payload is None:
        return {
            "status": "missing",
            "required_for": ["validation-ready"],
            "reasons": reasons,
        }

    missing_fields = [
        field
        for field in CAPTURE_SESSION_REQUIRED_FIELDS
        if not present_required_field(payload.get(field))
    ]
    status = "present" if not missing_fields else "invalid"
    return {
        "status": status,
        "required_for": ["validation-ready"],
        "reasons": [f"missing_capture_session_field:{field}" for field in missing_fields],
        "source_kind": payload.get("source_kind"),
        "camera_view": payload.get("camera_view"),
    }


def scorecard_payload(
    manifest: dict[str, Any] | None,
    key: str,
) -> tuple[dict[str, Any] | None, list[str]]:
    if manifest is None:
        return None, ["missing_motion_manifest"]

    inline = manifest.get(key)
    if isinstance(inline, dict):
        return inline, []

    scorecards = manifest.get("scorecards")
    nested_key = key.removesuffix("_scorecard")
    if isinstance(scorecards, dict) and isinstance(scorecards.get(nested_key), dict):
        return scorecards[nested_key], []

    for path_key in (f"{key}_path", f"{nested_key}_scorecard_path"):
        if path_key in manifest:
            payload, error = load_json_if_present(manifest.get(path_key))
            if payload is None:
                return None, [f"{path_key}:{error}"]
            return payload, []

    return None, [f"missing_{key}"]


def check_scorecard(
    manifest: dict[str, Any] | None,
    *,
    key: str,
    required_metrics: tuple[str, ...],
) -> dict[str, Any]:
    payload, reasons = scorecard_payload(manifest, key)
    if payload is None:
        return {
            "status": "missing",
            "required_for": ["validation-ready"],
            "reasons": reasons,
        }

    status = normalized_status(payload.get("status"))
    metrics = payload.get("metrics")
    missing_metrics: list[str] = []
    if not isinstance(metrics, dict):
        missing_metrics = list(required_metrics)
    else:
        missing_metrics = [field for field in required_metrics if field not in metrics]

    reasons = [f"missing_scorecard_metric:{field}" for field in missing_metrics]
    if status not in PASSED_SCORECARD_STATUSES:
        reasons.append(f"scorecard_status_not_passed:{status or 'missing'}")

    return {
        "status": "passed" if not reasons else "invalid",
        "required_for": ["validation-ready"],
        "decision": status or "missing",
        "reasons": reasons,
    }


def check_visual_review_decision(manifest: dict[str, Any] | None) -> dict[str, Any]:
    if manifest is None:
        return {
            "status": "missing",
            "required_for": ["guide-ready", "validation-ready"],
            "decision": "missing",
            "reasons": ["missing_motion_manifest"],
        }

    visual_review = manifest.get("visual_review")
    if not isinstance(visual_review, dict):
        return {
            "status": "missing",
            "required_for": ["guide-ready", "validation-ready"],
            "decision": "missing",
            "reasons": ["missing_visual_review_decision"],
        }

    decision = normalized_status(visual_review.get("status"))
    evidence_present = non_empty_string(visual_review.get("evidence")) is not None
    reasons: list[str] = []
    if decision not in PASSED_REVIEW_STATUSES:
        reasons.append(f"visual_review_status_not_passed:{decision or 'missing'}")
    if not evidence_present:
        reasons.append("missing_visual_review_evidence")

    if decision == "failed":
        status = "failed"
    elif reasons:
        status = "invalid"
    else:
        status = "passed"

    return {
        "status": status,
        "required_for": ["guide-ready", "validation-ready"],
        "decision": decision or "missing",
        "evidence_present": evidence_present,
        "reasons": reasons,
    }


def check_runtime_validation_set(manifest: dict[str, Any] | None) -> dict[str, Any]:
    if manifest is None:
        return {
            "status": "missing",
            "required_for": ["validation-ready"],
            "reasons": ["missing_motion_manifest"],
        }

    payload = manifest.get("runtime_validation_set") or manifest.get("validation_set")
    if not isinstance(payload, dict):
        return {
            "status": "missing",
            "required_for": ["validation-ready"],
            "reasons": ["missing_runtime_validation_set"],
        }

    status = normalized_status(payload.get("status"))
    clip_count = payload.get("clip_count")
    reasons: list[str] = []
    if status not in PASSED_SCORECARD_STATUSES:
        reasons.append(f"runtime_validation_set_status_not_passed:{status or 'missing'}")
    if not isinstance(clip_count, int) or clip_count < 5:
        reasons.append("runtime_validation_set_requires_at_least_5_clips")

    return {
        "status": "passed" if not reasons else "invalid",
        "required_for": ["validation-ready"],
        "decision": status or "missing",
        "clip_count": clip_count,
        "reasons": reasons,
    }


def factory_concept_checks(manifest: dict[str, Any] | None) -> dict[str, dict[str, Any]]:
    return {
        "capture_session_metadata": check_capture_session_metadata(manifest),
        "detector_agreement_scorecard": check_scorecard(
            manifest,
            key="detector_agreement_scorecard",
            required_metrics=DETECTOR_SCORECARD_REQUIRED_METRICS,
        ),
        "kinematic_scorecard": check_scorecard(
            manifest,
            key="kinematic_scorecard",
            required_metrics=KINEMATIC_SCORECARD_REQUIRED_METRICS,
        ),
        "human_visual_review_decision": check_visual_review_decision(manifest),
        "runtime_validation_set": check_runtime_validation_set(manifest),
    }


def manifest_has_any(manifest: dict[str, Any] | None, fields: tuple[str, ...]) -> bool:
    if manifest is None:
        return False
    return any(field in manifest and manifest.get(field) not in (None, "", []) for field in fields)


def profile_has_source_search(profile: dict[str, Any] | None) -> bool:
    if profile is None:
        return False
    capture = profile.get("capture")
    source_objects: list[dict[str, Any]] = [profile]
    if isinstance(capture, dict):
        source_objects.append(capture)
    return any(
        isinstance(source.get("rejected_candidates"), list)
        or isinstance(source.get("rejected_sources"), dict)
        or non_empty_string(source.get("source_page")) is not None
        or non_empty_string(source.get("source_media_url")) is not None
        or non_empty_string(source.get("clip")) is not None
        for source in source_objects
    )


def has_source_candidate(row: dict[str, Any], manifest: dict[str, Any] | None, profile: dict[str, Any] | None) -> bool:
    return (
        manifest_has_any(
            manifest,
            (
                "source_page",
                "source_media_url",
                "source_video",
                "source_label",
                "rejected_candidates",
                "rejected_sources",
            ),
        )
        or profile_has_source_search(profile)
        or bool(row.get("motion_profile"))
    )


def has_detector_reviewable_artifact(manifest: dict[str, Any] | None) -> bool:
    return manifest_has_any(
        manifest,
        (
            "raw_trace",
            "raw_review",
            "raw_review_sheet",
            "detector_agreement_scorecard",
            "detector_agreement_scorecard_path",
        ),
    )


def has_avatar_candidate(row: dict[str, Any], manifest: dict[str, Any] | None) -> bool:
    return bool(row.get("playable_jsonl")) or manifest_has_any(
        manifest,
        (
            "output_trace",
            "viewer_command",
            "kinematic_scorecard",
            "kinematic_scorecard_path",
        ),
    )


def guide_ready_blockers(
    row: dict[str, Any],
    manifest: dict[str, Any] | None,
    profile: dict[str, Any] | None,
    concepts: dict[str, dict[str, Any]],
) -> list[str]:
    blockers: list[str] = []
    gate_status = str(row.get("gate_status", ""))
    if gate_status == "reference_capture_required":
        blockers.append("reference_capture_required_gate")
    if not row.get("motion_profile"):
        blockers.append("missing_motion_profile")
    if bool(row.get("playable_jsonl")) and row.get("demo_status") == "invalid":
        blockers.append("invalid_playable_jsonl")
    if gate_status == "guide_ready" and not row.get("playable_jsonl"):
        blockers.append("guide_ready_missing_playable_jsonl")
    if manifest is None and (row.get("playable_jsonl") or gate_status == "guide_ready"):
        blockers.append("missing_motion_manifest")

    visual = concepts["human_visual_review_decision"]
    if has_avatar_candidate(row, manifest) or gate_status == "guide_ready":
        if visual["status"] == "failed":
            blockers.append("visual_review_failed")
        elif visual["status"] != "passed":
            blockers.extend(visual["reasons"])

    manifest_status = normalized_status(row.get("manifest_status"))
    if manifest_status.startswith("blocked") or manifest_status.startswith("rejected"):
        blockers.append(f"manifest_acceptance_not_promotable:{manifest_status}")

    profile_capture_status = capture_status(profile) if profile else str(row.get("capture_status", "missing"))
    if profile_capture_status == "pending_license_review":
        blockers.append("pending_source_license_review")
    if profile_capture_status in {"pending_first_party_capture", "pending_licensed_reference_clip"}:
        blockers.append(profile_capture_status)

    return sorted(set(blockers))


def validation_ready_blockers(
    row: dict[str, Any],
    concepts: dict[str, dict[str, Any]],
    guide_blockers: list[str],
    tier: str,
) -> list[str]:
    blockers: list[str] = []
    if tier != "guide-ready" or guide_blockers:
        blockers.append("not_guide_ready")

    for concept_name in (
        "capture_session_metadata",
        "detector_agreement_scorecard",
        "kinematic_scorecard",
        "runtime_validation_set",
    ):
        concept = concepts[concept_name]
        if concept["status"] != "passed" and concept["status"] != "present":
            blockers.extend(concept["reasons"])

    visual = concepts["human_visual_review_decision"]
    if visual["status"] != "passed":
        blockers.extend(visual["reasons"])

    if row.get("local_only_artifacts"):
        blockers.append("local_only_source_chain_artifacts")

    return sorted(set(blockers))


def classify_promotion_tier(
    row: dict[str, Any],
    manifest: dict[str, Any] | None,
    profile: dict[str, Any] | None,
    guide_blockers: list[str],
) -> str:
    if row.get("gate_status") == "guide_ready" and not guide_blockers:
        return "guide-ready"
    if has_avatar_candidate(row, manifest):
        return "avatar-demo-candidate"
    if has_detector_reviewable_artifact(manifest):
        return "detector-reviewable"
    if has_source_candidate(row, manifest, profile):
        return "source-candidate"
    return "recommendation-only"


def next_factory_action(
    row: dict[str, Any],
    tier: str,
    guide_blockers: list[str],
    validation_blockers: list[str],
) -> str:
    if tier == "guide-ready":
        if "local_only_source_chain_artifacts" in validation_blockers:
            return (
                "Keep guide-ready for the app, then backfill durable artifact storage, "
                "capture-session metadata, detector agreement, kinematic scorecard, "
                "and runtime validation clips before validation-ready."
            )
        return "Backfill factory capture/session scorecards and validation clips before validation-ready."
    if "visual_review_failed" in guide_blockers:
        return "Replace the failed avatar/source candidate and record a new passed human visual-review decision before guide promotion."
    if "reference_capture_required_gate" in guide_blockers:
        return str(row.get("next_action") or "Capture or license an exact source clip and keep this exercise quarantined until review passes.")
    if guide_blockers:
        return "Resolve guide blockers: " + ", ".join(guide_blockers)
    return str(row.get("next_action") or "Keep recommendation-only until motion evidence exists.")


def classify_factory_row(
    row: dict[str, Any],
    *,
    manifest: dict[str, Any] | None = None,
    profile: dict[str, Any] | None = None,
) -> dict[str, Any]:
    concepts = factory_concept_checks(manifest)
    guide_blockers = guide_ready_blockers(row, manifest, profile, concepts)
    tier = classify_promotion_tier(row, manifest, profile, guide_blockers)
    validation_blockers = validation_ready_blockers(row, concepts, guide_blockers, tier)
    validation_ready = tier == "guide-ready" and not validation_blockers
    final_tier = "validation-ready" if validation_ready else tier

    return {
        "exercise_id": row["exercise_id"],
        "label": row.get("label", row["exercise_id"]),
        "promotion_tier": final_tier,
        "tier_index": TIER_INDEX[final_tier],
        "guide_ready": tier == "guide-ready" and not guide_blockers,
        "validation_ready": validation_ready,
        "machine_reasons": {
            "guide_ready_blockers": guide_blockers,
            "validation_ready_blockers": validation_blockers,
            "warnings": sorted(set(row.get("missing", []))),
        },
        "current_signals": {
            "app_gate": row.get("gate_status"),
            "reference_status": row.get("reference_status"),
            "capture_status": row.get("capture_status"),
            "normalizer_status": row.get("normalizer_status"),
            "manifest_status": row.get("manifest_status"),
            "playable_jsonl": bool(row.get("playable_jsonl")),
            "local_only_artifacts": list(row.get("local_only_artifacts", [])),
        },
        "factory_concepts": concepts,
        "next_factory_action": next_factory_action(row, tier, guide_blockers, validation_blockers),
    }


def summarize_factory_rows(rows: list[dict[str, Any]]) -> dict[str, Any]:
    tier_counts = {tier: 0 for tier in PROMOTION_TIERS}
    for row in rows:
        tier_counts[row["promotion_tier"]] += 1
    return {
        "exercise_rows": len(rows),
        "tier_counts": tier_counts,
        "guide_ready": tier_counts["guide-ready"] + tier_counts["validation-ready"],
        "validation_ready": tier_counts["validation-ready"],
        "blocked_from_guide_ready": sum(
            1 for row in rows if row["machine_reasons"]["guide_ready_blockers"]
        ),
        "missing_detector_agreement_scorecards": sum(
            1
            for row in rows
            if row["factory_concepts"]["detector_agreement_scorecard"]["status"] == "missing"
        ),
        "missing_kinematic_scorecards": sum(
            1
            for row in rows
            if row["factory_concepts"]["kinematic_scorecard"]["status"] == "missing"
        ),
    }


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    profiles = load_profiles(args.profiles)
    gap_rows = report_motion_pipeline_gaps.build_exercise_rows(args)
    factory_rows: list[dict[str, Any]] = []
    for row in gap_rows:
        exercise_id = row["exercise_id"]
        manifest = load_manifest(args.motion_demos / f"{exercise_id}.jsonl")
        profile = profiles.get(exercise_id)
        factory_rows.append(
            classify_factory_row(row, manifest=manifest, profile=profile)
        )

    return {
        "schema_version": 1,
        "generated_by": "scripts/motion_reference/preflight_motion_data_factory.py",
        "inputs": {
            "presets": str(args.presets),
            "motion_demos": str(args.motion_demos),
            "profiles": str(args.profiles),
            "app_gate": str(args.app_gate),
        },
        "promotion_tiers": list(PROMOTION_TIERS),
        "summary": summarize_factory_rows(factory_rows),
        "exercises": factory_rows,
    }


def markdown_table(headers: list[str], rows: list[list[str]]) -> list[str]:
    output = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    for row in rows:
        escaped = [value.replace("|", "\\|").replace("\n", " ") for value in row]
        output.append("| " + " | ".join(escaped) + " |")
    return output


def write_markdown(report: dict[str, Any], path: Path) -> None:
    summary = report["summary"]
    tier_counts = summary["tier_counts"]
    lines: list[str] = [
        "# Motion Data Factory Preflight",
        "",
        "This report classifies app exercises into factory promotion tiers. It preserves the current app-gated guide-ready inventory while requiring explicit capture-session metadata, detector agreement scorecards, kinematic scorecards, and runtime validation clips before validation-ready.",
        "",
        "## Summary",
        "",
        f"- Exercise rows: {summary['exercise_rows']}",
        f"- Guide-ready: {summary['guide_ready']}",
        f"- Validation-ready: {summary['validation_ready']}",
        f"- Blocked from guide-ready: {summary['blocked_from_guide_ready']}",
        f"- Missing detector agreement scorecards: {summary['missing_detector_agreement_scorecards']}",
        f"- Missing kinematic scorecards: {summary['missing_kinematic_scorecards']}",
        "",
        "## Tier Counts",
        "",
    ]
    lines.extend(markdown_table(["Tier", "Rows"], [[tier, str(tier_counts[tier])] for tier in PROMOTION_TIERS]))
    lines.extend(["", "## Exercise Matrix", ""])
    lines.extend(
        markdown_table(
            ["Exercise", "Tier", "Guide blockers", "Validation blockers", "Next action"],
            [
                [
                    row["exercise_id"],
                    row["promotion_tier"],
                    "; ".join(row["machine_reasons"]["guide_ready_blockers"]) or "none",
                    "; ".join(row["machine_reasons"]["validation_ready_blockers"]) or "none",
                    row["next_factory_action"],
                ]
                for row in report["exercises"]
            ],
        )
    )
    lines.extend(
        [
            "",
            "## Factory Contract",
            "",
            "- `guide-ready` remains the app-visible motion-demo promotion tier.",
            "- `validation-ready` additionally requires explicit capture-session metadata, detector agreement scorecard, kinematic scorecard, passed visual review, runtime validation set, and non-local source-chain storage.",
            "- `reference_capture_required` exercises cannot become guide-ready from this report.",
            "",
        ]
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")


def write_json(report: dict[str, Any], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--presets",
        type=Path,
        default=repo_root / "Sources/CamiFitApp/Resources/Presets",
        help="directory of packaged exercise preset JSON files",
    )
    parser.add_argument(
        "--motion-demos",
        type=Path,
        default=repo_root / "Sources/CamiFitApp/Resources/MotionDemos",
        help="directory of packaged motion demo JSONL files",
    )
    parser.add_argument(
        "--profiles",
        type=Path,
        default=script_dir / "exercise_motion_profiles.json",
        help="motion profile registry",
    )
    parser.add_argument(
        "--app-gate",
        type=Path,
        default=repo_root / "Sources/CamiFitApp/AppExerciseTrackingGate.swift",
        help="Swift tracking gate file",
    )
    parser.add_argument(
        "--json-output",
        type=Path,
        default=repo_root / "dist/motion-reference/motion-data-factory-preflight.json",
        help="JSON report output path",
    )
    parser.add_argument(
        "--markdown-output",
        type=Path,
        default=repo_root / "dist/motion-reference/motion-data-factory-preflight.md",
        help="Markdown report output path",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    report = build_report(args)
    write_json(report, args.json_output)
    write_markdown(report, args.markdown_output)
    summary = report["summary"]
    tier_counts = summary["tier_counts"]
    print(
        "motion-data-factory-preflight "
        f"json={args.json_output} markdown={args.markdown_output} "
        f"exercises={summary['exercise_rows']} "
        f"guide_ready={summary['guide_ready']} validation_ready={summary['validation_ready']} "
        f"recommendation_only={tier_counts['recommendation-only']} "
        f"source_candidate={tier_counts['source-candidate']} "
        f"detector_reviewable={tier_counts['detector-reviewable']} "
        f"avatar_demo_candidate={tier_counts['avatar-demo-candidate']} "
        f"blocked_from_guide_ready={summary['blocked_from_guide_ready']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
