#!/usr/bin/env python3
"""Generate a human-readable motion reference gap report.

This report is intentionally non-promotional: it summarizes what the app can
ship today, what is still only recommendation-safe, and what source/reference
artifacts are missing before an exercise can be treated as guide-ready.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from audit_kg_motion_readiness import (
    candidate_catalog_slugs,
    graph_summary,
    kg_readiness,
    measurement_support,
    readiness_for_presets,
    report_status,
)
from audit_motion_coverage import (
    audit_demo,
    capture_status,
    declared_artifact_paths,
    has_accepted_reference_clip,
    is_pending_reference_capture,
    load_manifest,
    load_presets,
    load_profiles,
    load_swift_string_set,
    manifest_reference_acceptance_failures,
    pending_source_search_failures,
    reference_acceptance_failures,
    status_requires_demo,
)


PROMOTION_PRIORITY_HINTS: dict[str, tuple[int, str]] = {
    "bodyweight_plank": (
        10,
        "Core hold coverage is foundational and the app already has hold acceptance logic.",
    ),
    "machine_chest_supported_row": (
        20,
        "Adds a pulling pattern; current blocker is source/license review, not app modeling.",
    ),
    "bodyweight_jumping_jack": (
        30,
        "Useful conditioning archetype, but must remain quarantined until the visual extraction is clean.",
    ),
    "single_arm_dumbbell_preacher_curl": (
        40,
        "Common isolation movement; previous visual rig review failed, so source-preserving review is the gate.",
    ),
    "standing_miniband_hip_flexion": (
        50,
        "Adds hip-flexion rehab/accessory coverage once a clean licensed source is captured.",
    ),
    "suspension_tricep_press": (
        60,
        "Useful suspension pattern; promote only after replacing the failed visual rig candidate.",
    ),
}


REASON_LABELS = {
    "missing_motion_demo": "missing playable JSONL",
    "missing_motion_manifest": "missing motion manifest",
    "missing_reference_manifest": "missing reference manifest",
    "pending_licensed_reference_clip": "pending licensed reference clip",
    "pending_first_party_capture": "pending first-party capture",
    "visual_rig_review_failed": "visual rig review failed",
    "source_extraction_candidate_only": "source extraction is candidate-only",
    "pending_source_license_review": "pending source license review",
    "external_commons_license_review_needed": "external source license review needed",
    "motion_quality_gate_failed": "motion quality gate failed",
}


def compact_reason(reason: str) -> str:
    if reason.startswith("missing_reference_artifact:"):
        return reason.replace("missing_reference_artifact:", "missing artifact: ")
    if reason.startswith("missing_reference_path:"):
        return reason.replace("missing_reference_path:", "missing artifact path: ")
    if reason.startswith("missing_reference_metadata:"):
        return reason.replace("missing_reference_metadata:", "missing metadata: ")
    if reason.startswith("pending_source_search:"):
        return reason.replace("pending_source_search:", "pending source search: ")
    if reason.startswith("unaccepted_reference_clip:"):
        return reason.replace("unaccepted_reference_clip:", "unaccepted reference clip: ")
    return REASON_LABELS.get(reason, reason)


def normalizer_status(profile: dict[str, Any] | None) -> str:
    if not profile:
        return "missing"
    normalizer = profile.get("normalizer", {})
    if not isinstance(normalizer, dict):
        return "unknown"
    return str(normalizer.get("status", "unknown"))


def manifest_acceptance_status(manifest: dict[str, Any] | None) -> str:
    if manifest is None:
        return "missing"
    return str(manifest.get("acceptance_status", "unknown"))


def gate_status(exercise_id: str, guide_ready_ids: set[str], capture_required_ids: set[str]) -> str:
    if exercise_id in guide_ready_ids:
        return "guide_ready"
    if exercise_id in capture_required_ids:
        return "reference_capture_required"
    return "not_listed"


def exercise_label(preset: dict[str, Any] | None, exercise_id: str) -> str:
    if not preset:
        return exercise_id.replace("_", " ").title()
    value = preset.get("name") or preset.get("title") or preset.get("displayName")
    if isinstance(value, str) and value.strip():
        return value.strip()
    return exercise_id.replace("_", " ").title()


def classify_reference_status(
    *,
    profile: dict[str, Any] | None,
    demo_exists: bool,
    demo_ok: bool,
    manifest: dict[str, Any] | None,
    acceptance_failures: list[str],
    pending_failures: list[str],
) -> str:
    if profile is None:
        return "missing_profile"

    if has_accepted_reference_clip(profile):
        if not demo_exists:
            return "accepted_reference_missing_playable_jsonl"
        if not demo_ok:
            return "accepted_reference_invalid_playable_jsonl"
        if manifest is None:
            return "accepted_reference_missing_manifest"
        if acceptance_failures:
            return "accepted_reference_missing_provenance"
        return "provenance_complete_guide_ready"

    current_capture_status = capture_status(profile)
    current_normalizer_status = normalizer_status(profile)
    if current_capture_status == "pending_license_review":
        return "pending_source_license_review"
    if current_capture_status == "pending_visual_rig_review" or current_normalizer_status.startswith("blocked_"):
        return "blocked_visual_review"
    if is_pending_reference_capture(profile):
        if pending_failures:
            return "pending_capture_missing_search_ledger"
        return "pending_reference_capture"
    return f"not_promotable:{current_capture_status}"


def next_action_for_row(row: dict[str, Any]) -> str:
    status = row["reference_status"]
    exercise_id = row["exercise_id"]
    if status == "provenance_complete_guide_ready" and row.get("local_only_artifacts"):
        return "Move source-chain artifacts out of ignored local-only storage or mirror them into a durable artifact store used by CI/release."
    if status == "accepted_reference_missing_provenance":
        return "Backfill source video, raw trace, output trace, normalizer hash, and live-app review artifact integrity."
    if status == "accepted_reference_missing_playable_jsonl":
        return "Package the accepted normalized JSONL or move the profile back to reference-capture-required."
    if status == "accepted_reference_invalid_playable_jsonl":
        return "Fix the bundled JSONL so the structural/loop/contact audit passes before app promotion."
    if status == "pending_source_license_review":
        return "Resolve license review, then run source extraction, normalizer, visual review, engine replay, and live-app review."
    if status == "blocked_visual_review":
        return "Replace the failed visual candidate with a clean source-preserving capture; do not promote the existing trace."
    if status == "pending_capture_missing_search_ledger":
        return "Record source-search/rejected-candidate evidence before leaving this exercise in the catalog."
    if status == "pending_reference_capture":
        return "Capture or license a source clip, extract raw MediaPipe, normalize, review, replay, and promote only after strict audit passes."
    if status == "missing_profile":
        return "Add a motion profile before exposing visuals or validation claims."
    if row["gate_status"] == "not_listed" and row["playable_jsonl"]:
        return "Either add this playable trace to the guide-ready gate or remove it from app resources."
    if exercise_id in PROMOTION_PRIORITY_HINTS:
        return PROMOTION_PRIORITY_HINTS[exercise_id][1]
    return "Keep recommendation-only until exact source-derived motion support exists."


def build_exercise_rows(args: argparse.Namespace) -> list[dict[str, Any]]:
    presets = load_presets(args.presets)
    profiles = load_profiles(args.profiles)
    playable_ids = {path.stem for path in args.motion_demos.glob("*.jsonl")}
    manifest_ids = {
        path.name.removesuffix(".manifest.json")
        for path in args.motion_demos.glob("*.manifest.json")
    }
    guide_ready_ids = load_swift_string_set(args.app_gate, "guideReadyPresetIDs")
    capture_required_ids = load_swift_string_set(args.app_gate, "referenceCaptureRequiredPresetIDs")

    exercise_ids = sorted(
        set(presets)
        | set(profiles)
        | playable_ids
        | manifest_ids
        | guide_ready_ids
        | capture_required_ids
    )

    rows: list[dict[str, Any]] = []
    for exercise_id in exercise_ids:
        profile = profiles.get(exercise_id)
        preset = presets.get(exercise_id)
        demo_path = args.motion_demos / f"{exercise_id}.jsonl"
        demo_exists = demo_path.exists()
        demo_ok = False
        demo_frame_count = 0
        demo_failures: list[str] = []
        if demo_exists and profile is not None:
            demo_audit = audit_demo(demo_path, profile)
            demo_ok = demo_audit.ok
            demo_frame_count = demo_audit.frame_count
            if not demo_audit.ok:
                if demo_audit.malformed_lines:
                    demo_failures.append("malformed_jsonl_lines")
                if demo_audit.timestamp_errors:
                    demo_failures.append("timestamp_errors")
                if demo_audit.missing_required:
                    demo_failures.append("missing_required_landmarks")
                if demo_audit.missing_contacts:
                    demo_failures.append("missing_contact_landmarks")
                if demo_audit.non_finite_values:
                    demo_failures.append("non_finite_landmark_values")
                if demo_audit.out_of_bounds_landmarks:
                    demo_failures.append("out_of_bounds_landmarks")
                if demo_audit.max_contact_delta is not None and demo_audit.max_contact_delta > 0.001:
                    demo_failures.append("contact_lock_delta_too_large")
                if demo_audit.max_loop_delta is not None and demo_audit.max_loop_delta > 0.002:
                    demo_failures.append("loop_boundary_delta_too_large")

        manifest = load_manifest(demo_path)
        artifact_paths = declared_artifact_paths(manifest) if manifest is not None else []
        local_only_artifacts = list(dict.fromkeys(
            value
            for _, value in artifact_paths
            if value == "dist" or value.startswith("dist/")
        ))
        acceptance_failures: list[str] = []
        pending_failures: list[str] = []
        profile_failures: list[str] = []
        if profile is not None:
            acceptance_failures.extend(reference_acceptance_failures(profile))
            acceptance_failures.extend(manifest_reference_acceptance_failures(profile, manifest))
            pending_failures.extend(pending_source_search_failures(profile, manifest))
            if status_requires_demo(str(profile.get("viewer_status", ""))) and not demo_exists:
                profile_failures.append("missing_motion_demo")

        missing = [compact_reason(reason) for reason in (
            profile_failures + demo_failures + acceptance_failures + pending_failures
        )]
        gate = gate_status(exercise_id, guide_ready_ids, capture_required_ids)
        row = {
            "exercise_id": exercise_id,
            "label": exercise_label(preset, exercise_id),
            "packaged_preset": exercise_id in presets,
            "motion_profile": exercise_id in profiles,
            "gate_status": gate,
            "playable_jsonl": demo_exists,
            "demo_status": "ok" if demo_ok else ("invalid" if demo_exists else "missing"),
            "demo_frame_count": demo_frame_count,
            "manifest_status": manifest_acceptance_status(manifest),
            "viewer_status": str(profile.get("viewer_status", "missing")) if profile else "missing",
            "measurement_status": str(profile.get("measurement_status", "missing")) if profile else "missing",
            "capture_status": capture_status(profile) if profile else "missing",
            "normalizer_status": normalizer_status(profile),
            "artifact_paths": [
                {"label": label, "path": value}
                for label, value in artifact_paths
            ],
            "local_only_artifacts": local_only_artifacts,
            "reference_status": classify_reference_status(
                profile=profile,
                demo_exists=demo_exists,
                demo_ok=demo_ok,
                manifest=manifest,
                acceptance_failures=acceptance_failures,
                pending_failures=pending_failures,
            ),
            "missing": sorted(set(missing)),
        }
        row["next_action"] = next_action_for_row(row)
        priority_hint = PROMOTION_PRIORITY_HINTS.get(exercise_id)
        row["promotion_priority"] = priority_hint[0] if priority_hint else None
        rows.append(row)

    return rows


def build_kg_report(args: argparse.Namespace) -> dict[str, Any]:
    preset_readiness = readiness_for_presets(args.presets, args.profiles, args.motion_demos)
    graph_rows = {
        "shipped": kg_readiness("shipped", args.shipped_kg, preset_readiness),
        "generated": kg_readiness("generated", args.generated_kg, preset_readiness),
    }
    catalog_slugs = candidate_catalog_slugs(args.candidate_exercises)
    generated_slugs = {
        row.kg_id.split(":", 1)[1]
        for row in graph_rows["generated"]
        if row.kg_id.startswith("Exercise:")
    }
    return {
        "app_presets": {
            "total": len(preset_readiness),
            "guide_ready": sum(1 for preset in preset_readiness.values() if preset.ready),
        },
        "graphs": {
            graph_name: {
                "summary": graph_summary(rows),
                "rows": [
                    {
                        "kg_id": row.kg_id,
                        "label": row.label,
                        "mapped_preset_id": row.mapped_preset_id,
                        "mapping_kind": row.mapping_kind,
                        "mapping_source": row.mapping_source,
                        "status": report_status(row),
                        "audit_status": row.status,
                        "measurement_support": measurement_support(row),
                        "reasons": list(row.reasons),
                    }
                    for row in rows
                ],
            }
            for graph_name, rows in graph_rows.items()
        },
        "generated_missing_candidate_exercises": sorted(catalog_slugs - generated_slugs),
    }


def summarize(rows: list[dict[str, Any]], kg_report: dict[str, Any]) -> dict[str, Any]:
    guide_ready_rows = [row for row in rows if row["gate_status"] == "guide_ready"]
    pending_rows = [row for row in rows if row["gate_status"] == "reference_capture_required"]
    provenance_complete = [
        row
        for row in guide_ready_rows
        if row["reference_status"] == "provenance_complete_guide_ready"
    ]
    accepted_missing_provenance = [
        row
        for row in guide_ready_rows
        if row["reference_status"] == "accepted_reference_missing_provenance"
    ]
    blocked_visual = [
        row
        for row in rows
        if row["reference_status"] == "blocked_visual_review"
    ]
    guide_ready_local_only_artifacts = [
        row
        for row in guide_ready_rows
        if row["local_only_artifacts"]
    ]
    return {
        "exercise_rows": len(rows),
        "packaged_presets": sum(1 for row in rows if row["packaged_preset"]),
        "motion_profiles": sum(1 for row in rows if row["motion_profile"]),
        "playable_jsonls": sum(1 for row in rows if row["playable_jsonl"]),
        "app_gate_guide_ready": len(guide_ready_rows),
        "app_gate_reference_capture_required": len(pending_rows),
        "provenance_complete_guide_ready": len(provenance_complete),
        "guide_ready_missing_provenance": len(accepted_missing_provenance),
        "guide_ready_with_local_only_artifacts": len(guide_ready_local_only_artifacts),
        "blocked_visual_review": len(blocked_visual),
        "kg_generated": kg_report["graphs"]["generated"]["summary"],
        "kg_shipped": kg_report["graphs"]["shipped"]["summary"],
    }


def promotion_lanes(rows: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    backfill = [
        row
        for row in rows
        if row["gate_status"] == "guide_ready"
        and row["reference_status"] == "accepted_reference_missing_provenance"
    ]
    prioritized = [
        row
        for row in rows
        if row.get("promotion_priority") is not None
        and row["reference_status"] != "provenance_complete_guide_ready"
    ]
    prioritized.sort(key=lambda row: int(row["promotion_priority"]))
    remaining = [
        row
        for row in rows
        if row["gate_status"] == "reference_capture_required"
        and row not in prioritized
    ]
    return {
        "artifact_storage_risk": [
            row
            for row in rows
            if row["gate_status"] == "guide_ready"
            and row["local_only_artifacts"]
        ],
        "provenance_backfill_first": backfill,
        "next_reference_promotions": prioritized,
        "remaining_reference_capture_required": remaining,
    }


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    rows = build_exercise_rows(args)
    kg_report = build_kg_report(args)
    return {
        "schema_version": 1,
        "generated_by": "scripts/motion_reference/report_motion_pipeline_gaps.py",
        "inputs": {
            "presets": str(args.presets),
            "motion_demos": str(args.motion_demos),
            "profiles": str(args.profiles),
            "app_gate": str(args.app_gate),
            "shipped_kg": str(args.shipped_kg),
            "generated_kg": str(args.generated_kg),
            "candidate_exercises": str(args.candidate_exercises),
        },
        "summary": summarize(rows, kg_report),
        "exercises": rows,
        "promotion_lanes": {
            lane: [
                {
                    "exercise_id": row["exercise_id"],
                    "label": row["label"],
                    "reference_status": row["reference_status"],
                    "gate_status": row["gate_status"],
                    "capture_status": row["capture_status"],
                    "normalizer_status": row["normalizer_status"],
                    "local_only_artifacts": row["local_only_artifacts"],
                    "next_action": row["next_action"],
                    "missing": row["missing"],
                }
                for row in lane_rows
            ]
            for lane, lane_rows in promotion_lanes(rows).items()
        },
        "kg": kg_report,
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
    lines: list[str] = [
        "# Motion Reference Gap Report",
        "",
        "This report is generated from app presets, motion profiles, bundled MotionDemos, the app tracking gate, and KG artifacts.",
        "",
        "## Summary",
        "",
        f"- Packaged presets: {summary['packaged_presets']}",
        f"- Motion profiles: {summary['motion_profiles']}",
        f"- Packaged playable JSONLs: {summary['playable_jsonls']}",
        f"- App gate guide-ready IDs: {summary['app_gate_guide_ready']}",
        f"- Provenance-complete guide-ready IDs: {summary['provenance_complete_guide_ready']}",
        f"- Guide-ready IDs still missing source-chain provenance: {summary['guide_ready_missing_provenance']}",
        f"- Guide-ready IDs relying on local-only `dist/` artifacts: {summary['guide_ready_with_local_only_artifacts']}",
        f"- Reference-capture-required IDs: {summary['app_gate_reference_capture_required']}",
        f"- Blocked visual-review rows: {summary['blocked_visual_review']}",
        "",
        "## Artifact Storage Risk",
        "",
    ]

    artifact_risk = report["promotion_lanes"]["artifact_storage_risk"]
    if artifact_risk:
        lines.extend(
            markdown_table(
                ["Exercise", "Local-only artifacts", "Next action"],
                [
                    [
                        row["exercise_id"],
                        "; ".join(row["local_only_artifacts"]),
                        row["next_action"],
                    ]
                    for row in artifact_risk
                ],
            )
        )
    else:
        lines.append("No guide-ready traces rely on local-only `dist/` source-chain artifacts.")

    lines.extend(["", "## Release-Critical Backfill", ""])

    backfill = report["promotion_lanes"]["provenance_backfill_first"]
    if backfill:
        lines.extend(
            markdown_table(
                ["Exercise", "Status", "Missing", "Next action"],
                [
                    [
                        row["exercise_id"],
                        row["reference_status"],
                        "; ".join(row["missing"]) or "none",
                        row["next_action"],
                    ]
                    for row in backfill
                ],
            )
        )
    else:
        lines.append("No guide-ready provenance backfill gaps found.")

    lines.extend(["", "## Next Reference Promotions", ""])
    next_promotions = report["promotion_lanes"]["next_reference_promotions"]
    if next_promotions:
        lines.extend(
            markdown_table(
                ["Exercise", "Current blocker", "Capture", "Normalizer", "Next action"],
                [
                    [
                        row["exercise_id"],
                        row["reference_status"],
                        row["capture_status"],
                        row["normalizer_status"],
                        row["next_action"],
                    ]
                    for row in next_promotions
                ],
            )
        )
    else:
        lines.append("No prioritized pending promotions found.")

    lines.extend(["", "## Exercise Matrix", ""])
    lines.extend(
        markdown_table(
            ["Exercise", "Gate", "Playable", "Manifest", "Reference status", "Missing count"],
            [
                [
                    row["exercise_id"],
                    row["gate_status"],
                    "yes" if row["playable_jsonl"] else "no",
                    row["manifest_status"],
                    row["reference_status"],
                    str(len(row["missing"])),
                ]
                for row in report["exercises"]
            ],
        )
    )

    lines.extend(["", "## KG Readiness", ""])
    kg_rows: list[list[str]] = []
    for graph_name, graph in report["kg"]["graphs"].items():
        summary_row = graph["summary"]
        kg_rows.append(
            [
                graph_name,
                str(summary_row["kg_exercises"]),
                str(summary_row["guide_ready"]),
                str(summary_row["archetype_demo_only"]),
                str(summary_row["recommend_only"]),
                str(summary_row["mapped_incomplete"]),
            ]
        )
    lines.extend(
        markdown_table(
            ["Graph", "Exercises", "Guide-ready", "Archetype demo", "Recommend-only", "Mapped incomplete"],
            kg_rows,
        )
    )

    lines.extend(
        [
            "",
            "## Promotion Contract",
            "",
            "An exercise should only move to guide-ready after source video, raw MediaPipe trace, normalizer, output trace, visual review, engine replay, live-app review, and artifact hashes all survive the strict audit.",
            "Family or archetype mappings may help recommendations, but they do not unlock exact measurement support.",
            "",
        ]
    )

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")


def write_json(report: dict[str, Any], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
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
        "--shipped-kg",
        type=Path,
        default=repo_root / "Sources/KGKit/Resources/Artifact/kg_artifact.v0.json",
        help="KG artifact bundled into KGKit",
    )
    parser.add_argument(
        "--generated-kg",
        type=Path,
        default=repo_root / "kg-canonical/graph/generated/assessment_exercise_kg.generated.json",
        help="generated candidate-assessment exercise KG",
    )
    parser.add_argument(
        "--candidate-exercises",
        type=Path,
        default=repo_root / "data/golden/candidate-assessment/data/exercises.json",
        help="frozen candidate-assessment exercise catalog",
    )
    parser.add_argument(
        "--json-output",
        type=Path,
        default=repo_root / "dist/motion-reference/gap-report.json",
        help="JSON report output path",
    )
    parser.add_argument(
        "--markdown-output",
        type=Path,
        default=repo_root / "dist/motion-reference/gap-report.md",
        help="Markdown report output path",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = build_report(args)
    write_json(report, args.json_output)
    write_markdown(report, args.markdown_output)
    summary = report["summary"]
    print(
        "motion-gap-report "
        f"json={args.json_output} markdown={args.markdown_output} "
        f"presets={summary['packaged_presets']} playable_jsonls={summary['playable_jsonls']} "
        f"guide_ready={summary['app_gate_guide_ready']} "
        f"provenance_complete={summary['provenance_complete_guide_ready']} "
        f"guide_ready_missing_provenance={summary['guide_ready_missing_provenance']} "
        f"reference_capture_required={summary['app_gate_reference_capture_required']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
