#!/usr/bin/env python3
"""Audit KG exercise nodes against runnable app presets and motion demos."""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from audit_motion_coverage import audit_demo, load_manifest, load_presets, load_profiles, status_requires_demo
from audit_motion_coverage import audit_quality_gates, capture_status, quality_gate_enforced, reference_acceptance_failures
from audit_motion_coverage import has_accepted_reference_clip, manifest_reference_acceptance_failures


MAPPING_PROPERTY_KEYS = (
    "camifit_preset_id",
    "app_preset_id",
    "runtime_preset_id",
    "preset_id",
)

EXACT_KG_PRESET_IDS = {
    "Exercise:jumping_jack": "bodyweight_jumping_jack",
    "Exercise:resistance_band_reverse_curl": "resistance_band_reverse_curl",
    "Exercise:standing_miniband_hip_flexion": "standing_miniband_hip_flexion",
    "Exercise:single_arm_chest_supported_incline_row": "single_arm_chest_supported_incline_row",
    "Exercise:machine_chest_supported_row": "machine_chest_supported_row",
    "Exercise:suspension_tricep_press": "suspension_tricep_press",
    "Exercise:wide_grip_preacher_curl_with_ez_bar": "wide_grip_preacher_curl_with_ez_bar",
}

QUARANTINED_KG_EXERCISE_IDS = {
    "Exercise:jumping_jack": (
        "user_rejected_app_visible_motion",
        "pending_clean_licensed_reference_clip",
    ),
}


@dataclass(frozen=True)
class ArchetypeMappingRule:
    preset_id: str
    family_ids: tuple[str, ...]
    label_contains: tuple[str, ...]


ARCHETYPE_MAPPING_RULES = (
    ArchetypeMappingRule(
        preset_id="bodyweight_lunge",
        family_ids=("ExerciseFamily:lunge_family",),
        label_contains=(),
    ),
    ArchetypeMappingRule(
        preset_id="bodyweight_squat",
        family_ids=("ExerciseFamily:squat_family",),
        label_contains=(),
    ),
    ArchetypeMappingRule(
        preset_id="bodyweight_pushup",
        family_ids=("ExerciseFamily:press_family",),
        label_contains=("push-up",),
    ),
    ArchetypeMappingRule(
        preset_id="bodyweight_plank",
        family_ids=("ExerciseFamily:core_family",),
        label_contains=("plank",),
    ),
)

CANONICAL_PENDING_CAPTURE_ALLOWLIST: set[str] = set()

PENDING_CAPTURE_REASON_CODES = {
    "pending_first_party_capture": (
        "pending_first_party_capture",
        "reference_capture_required",
    ),
    "pending_licensed_reference_clip": (
        "pending_licensed_reference_clip",
        "synthetic_archetype_trace_not_guide_ready",
    ),
    "pending_visual_rig_review": (
        "visual_rig_review_failed",
        "source_extraction_candidate_only",
    ),
    "pending_license_review": (
        "pending_source_license_review",
        "external_commons_license_review_needed",
    ),
}


@dataclass(frozen=True)
class PresetReadiness:
    preset_id: str
    profile_status: str
    demo_status: str
    ready: bool
    reasons: tuple[str, ...]


@dataclass(frozen=True)
class KGMapping:
    preset_id: str
    kind: str
    source: str


@dataclass(frozen=True)
class KGReadiness:
    graph_name: str
    kg_id: str
    label: str
    mapped_preset_id: str | None
    mapping_kind: str | None
    mapping_source: str | None
    status: str
    reasons: tuple[str, ...]


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")


def exercise_nodes(path: Path) -> list[dict[str, Any]]:
    payload = load_json(path)
    return exercise_nodes_from_payload(payload)


def exercise_nodes_from_payload(payload: dict[str, Any]) -> list[dict[str, Any]]:
    return sorted(
        (node for node in payload.get("nodes", []) if node.get("type") == "Exercise"),
        key=lambda node: str(node.get("id", "")),
    )


def variant_families_by_exercise(payload: dict[str, Any]) -> dict[str, set[str]]:
    families: dict[str, set[str]] = {}
    for edge in payload.get("edges", []):
        if edge.get("predicate") != "VARIANT_OF":
            continue
        source = edge.get("source")
        target = edge.get("target")
        if isinstance(source, str) and isinstance(target, str):
            families.setdefault(source, set()).add(target)
    return families


def candidate_catalog_slugs(path: Path) -> set[str]:
    payload = load_json(path)
    if not isinstance(payload, list):
        raise SystemExit(f"{path}: expected candidate exercise list")
    return {slug(str(item["name"])) for item in payload}


def pending_capture_reasons(profile: dict[str, Any]) -> list[str]:
    status = capture_status(profile)
    reasons = list(PENDING_CAPTURE_REASON_CODES.get(status, ()))
    normalizer = profile.get("normalizer", {})
    normalizer_status = ""
    if isinstance(normalizer, dict):
        normalizer_status = str(normalizer.get("status", ""))
    if normalizer_status.startswith("blocked_") and normalizer_status not in reasons:
        reasons.append(normalizer_status)
    if not reasons and status.startswith("pending_"):
        reasons.append(status)
    return reasons


def readiness_for_presets(
    presets_path: Path,
    profiles_path: Path,
    motion_demos_path: Path,
) -> dict[str, PresetReadiness]:
    presets = load_presets(presets_path)
    profiles = load_profiles(profiles_path)
    readiness: dict[str, PresetReadiness] = {}

    for preset_id in sorted(presets):
        profile = profiles.get(preset_id)
        reasons: list[str] = []
        if profile is None:
            readiness[preset_id] = PresetReadiness(
                preset_id=preset_id,
                profile_status="missing",
                demo_status="unchecked",
                ready=False,
                reasons=("missing_motion_profile",),
            )
            continue

        profile_status = str(profile.get("viewer_status", "unknown"))
        requires_demo = status_requires_demo(profile_status)
        demo_path = motion_demos_path / f"{preset_id}.jsonl"
        if not demo_path.exists():
            if requires_demo:
                reasons.append("missing_motion_demo")
            else:
                reasons.extend(pending_capture_reasons(profile))
            readiness[preset_id] = PresetReadiness(
                preset_id=preset_id,
                profile_status=profile_status,
                demo_status="missing",
                ready=False,
                reasons=tuple(reasons or ["demo_not_required_yet"]),
            )
            continue

        audit = audit_demo(demo_path, profile)
        manifest = load_manifest(demo_path)
        if manifest is None:
            reasons.append("missing_motion_manifest")
        if not audit.ok:
            reasons.append("invalid_motion_demo")
        if manifest is not None and manifest.get("exercise_id") != preset_id:
            reasons.append("motion_manifest_exercise_id_mismatch")
        for failure in reference_acceptance_failures(profile):
            reasons.append(failure)
        for failure in manifest_reference_acceptance_failures(profile, manifest):
            reasons.append(f"reference_manifest_{failure}")
        quality = audit_quality_gates(profile, audit, manifest)
        if quality.failures and quality_gate_enforced(profile):
            reasons.append("motion_quality_gate_failed")
        if (
            preset_id not in CANONICAL_PENDING_CAPTURE_ALLOWLIST
            and not has_accepted_reference_clip(profile)
        ):
            capture = profile.get("capture", {})
            capture_status = capture.get("status") if isinstance(capture, dict) else "unknown"
            if capture_status in {"pending_first_party_capture", "pending_licensed_reference_clip"}:
                reasons.append("pending_licensed_reference_clip")
            else:
                reasons.append(f"unaccepted_reference_clip:{capture_status}")

        readiness[preset_id] = PresetReadiness(
            preset_id=preset_id,
            profile_status=profile_status,
            demo_status="ok" if audit.ok and manifest is not None else "invalid",
            ready=not reasons,
            reasons=tuple(reasons),
        )

    return readiness


def exact_mapping(node: dict[str, Any], preset_ids: set[str]) -> KGMapping | None:
    properties = node.get("properties")
    if not isinstance(properties, dict):
        properties = {}

    kg_id = str(node.get("id", ""))
    mapped_preset_id = EXACT_KG_PRESET_IDS.get(kg_id)
    if mapped_preset_id is not None:
        return KGMapping(
            preset_id=mapped_preset_id,
            kind="exact_id",
            source="kg_id",
        )

    for key in MAPPING_PROPERTY_KEYS:
        value = properties.get(key)
        if isinstance(value, str) and value:
            return KGMapping(
                preset_id=value,
                kind="exact_property",
                source=f"properties.{key}",
            )

    if kg_id.startswith("Exercise:"):
        kg_slug = kg_id.split(":", 1)[1]
        if kg_slug in preset_ids:
            return KGMapping(
                preset_id=kg_slug,
                kind="exact_id",
                source="kg_id",
            )

    label_slug = slug(str(node.get("label", "")))
    if label_slug in preset_ids:
        return KGMapping(
            preset_id=label_slug,
            kind="exact_label",
            source="label_slug",
        )

    return None


def archetype_mapping(node: dict[str, Any], family_ids: set[str]) -> KGMapping | None:
    label = str(node.get("label", "")).lower()
    for rule in ARCHETYPE_MAPPING_RULES:
        for family_id in rule.family_ids:
            if family_id in family_ids:
                return KGMapping(
                    preset_id=rule.preset_id,
                    kind="family_archetype",
                    source=family_id,
                )
        for term in rule.label_contains:
            if term in label:
                return KGMapping(
                    preset_id=rule.preset_id,
                    kind="label_archetype",
                    source=f"label_contains:{term}",
                )
    return None


def mapping_for_node(
    node: dict[str, Any],
    preset_ids: set[str],
    family_ids: set[str],
) -> KGMapping | None:
    return exact_mapping(node, preset_ids) or archetype_mapping(node, family_ids)


def kg_readiness(
    graph_name: str,
    graph_path: Path,
    preset_readiness: dict[str, PresetReadiness],
) -> list[KGReadiness]:
    preset_ids = set(preset_readiness)
    payload = load_json(graph_path)
    families_by_exercise = variant_families_by_exercise(payload)
    rows: list[KGReadiness] = []
    for node in exercise_nodes_from_payload(payload):
        kg_id = str(node.get("id", ""))
        label = str(node.get("label", ""))
        if kg_id in QUARANTINED_KG_EXERCISE_IDS:
            rows.append(
                KGReadiness(
                    graph_name=graph_name,
                    kg_id=kg_id,
                    label=label,
                    mapped_preset_id=None,
                    mapping_kind=None,
                    mapping_source=None,
                    status="quarantined",
                    reasons=QUARANTINED_KG_EXERCISE_IDS[kg_id],
                )
            )
            continue

        mapping = mapping_for_node(
            node,
            preset_ids,
            families_by_exercise.get(kg_id, set()),
        )
        if mapping is None:
            rows.append(
                KGReadiness(
                    graph_name=graph_name,
                    kg_id=kg_id,
                    label=label,
                    mapped_preset_id=None,
                    mapping_kind=None,
                    mapping_source=None,
                    status="recommend_only",
                    reasons=("no_app_preset_mapping",),
                )
            )
            continue

        preset = preset_readiness.get(mapping.preset_id)
        if preset is None:
            rows.append(
                KGReadiness(
                    graph_name=graph_name,
                    kg_id=kg_id,
                    label=label,
                    mapped_preset_id=mapping.preset_id,
                    mapping_kind=mapping.kind,
                    mapping_source=mapping.source,
                    status="mapped_missing_preset",
                    reasons=("mapped_preset_not_packaged",),
                )
            )
            continue

        is_archetype = mapping.kind in {"family_archetype", "label_archetype"}
        if preset.ready and is_archetype:
            status = "archetype_demo_only"
            reasons = (
                "uses_packaged_preset_demo_as_archetype",
                "exact_kg_exercise_measurement_not_supported",
            )
        elif preset.ready:
            status = "guide_ready"
            reasons = preset.reasons
        elif is_archetype:
            status = "archetype_motion_incomplete"
            reasons = preset.reasons
        else:
            status = "exact_motion_incomplete"
            reasons = preset.reasons

        rows.append(
            KGReadiness(
                graph_name=graph_name,
                kg_id=kg_id,
                label=label,
                mapped_preset_id=mapping.preset_id,
                mapping_kind=mapping.kind,
                mapping_source=mapping.source,
                status=status,
                reasons=reasons,
            )
        )
    return rows


def print_preset_lines(readiness: dict[str, PresetReadiness]) -> None:
    for preset in readiness.values():
        reason = ",".join(preset.reasons) if preset.reasons else "none"
        print(
            "kg-motion-readiness "
            f"app_preset={preset.preset_id} status={'guide_ready' if preset.ready else 'not_ready'} "
            f"profile={preset.profile_status} demo={preset.demo_status} reasons={reason}"
        )


def print_kg_lines(rows: list[KGReadiness], summary_only: bool) -> None:
    if summary_only:
        return
    for row in rows:
        mapped = row.mapped_preset_id or "missing"
        kind = row.mapping_kind or "none"
        source = row.mapping_source or "none"
        reason = ",".join(row.reasons) if row.reasons else "none"
        print(
            "kg-motion-readiness "
            f"graph={row.graph_name} kg_id={row.kg_id} label={json.dumps(row.label)} "
            f"status={report_status(row)} audit_status={row.status} "
            f"mapped_preset={mapped} mapping_kind={kind} mapping_source={source} reasons={reason}"
        )


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
        "--summary-only",
        action="store_true",
        help="print only preset readiness and graph summaries",
    )
    parser.add_argument(
        "--require-all-kg-viewer-ready",
        action="store_true",
        help="fail unless every KG exercise maps to a viewer-ready packaged preset",
    )
    parser.add_argument(
        "--write-report",
        type=Path,
        help="optional JSON report path for KG-to-motion readiness classifications",
    )
    return parser.parse_args()


def report_status(row: KGReadiness) -> str:
    if row.status == "guide_ready":
        return "guide_ready"
    if row.status == "archetype_demo_only":
        return "archetype_demo_only"
    return "recommend_only"


def measurement_support(row: KGReadiness) -> str:
    if report_status(row) == "guide_ready":
        return "exact_packaged_preset_motion_support"
    if report_status(row) == "archetype_demo_only":
        return "packaged_preset_archetype_demo_only"
    return "none"


def archetype_mapping_table() -> list[dict[str, Any]]:
    return [
        {
            "preset_id": rule.preset_id,
            "family_ids": list(rule.family_ids),
            "label_contains": list(rule.label_contains),
            "status_when_preset_guide_ready": "archetype_demo_only",
            "measurement_support": (
                "Packaged preset demo only; the exact KG exercise remains "
                "recommend_only for measurement."
            ),
        }
        for rule in ARCHETYPE_MAPPING_RULES
    ]


def graph_summary(rows: list[KGReadiness]) -> dict[str, int]:
    classifications = [report_status(row) for row in rows]
    return {
        "kg_exercises": len(rows),
        "guide_ready": classifications.count("guide_ready"),
        "archetype_demo_only": classifications.count("archetype_demo_only"),
        "recommend_only": classifications.count("recommend_only"),
        "mapped_incomplete": sum(
            1
            for row in rows
            if row.status
            in {
                "mapped_missing_preset",
                "exact_motion_incomplete",
                "archetype_motion_incomplete",
            }
        ),
    }


def write_report(
    path: Path,
    preset_readiness: dict[str, PresetReadiness],
    graph_rows: dict[str, list[KGReadiness]],
    missing_from_generated: list[str],
) -> None:
    payload = {
        "schema_version": 1,
        "generated_by": "scripts/motion_reference/audit_kg_motion_readiness.py",
        "classification_values": [
            "guide_ready",
            "archetype_demo_only",
            "recommend_only",
            "filtered",
        ],
        "classification_semantics": {
            "guide_ready": "Exact KG exercise maps to a packaged preset with valid motion support.",
            "archetype_demo_only": (
                "Explicit family or label archetype mapping to a packaged guide-ready preset; "
                "does not claim exact KG exercise measurement support."
            ),
            "recommend_only": "Exercise can appear as KG recommendation evidence but has no motion guide claim.",
            "filtered": "Exercise was removed by resolver or safety constraints before app projection.",
        },
        "archetype_mapping_table": archetype_mapping_table(),
        "app_presets": [
            {
                "preset_id": preset.preset_id,
                "status": "guide_ready" if preset.ready else "not_ready",
                "profile_status": preset.profile_status,
                "demo_status": preset.demo_status,
                "reasons": list(preset.reasons),
            }
            for preset in preset_readiness.values()
        ],
        "graphs": {
            graph_name: [
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
            ]
            for graph_name, rows in graph_rows.items()
        },
        "summary": {
            graph_name: graph_summary(rows)
            for graph_name, rows in graph_rows.items()
        },
        "generated_missing_candidate_exercises": missing_from_generated,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"kg-motion-readiness report={path}")


def main() -> int:
    args = parse_args()
    preset_readiness = readiness_for_presets(args.presets, args.profiles, args.motion_demos)
    print_preset_lines(preset_readiness)

    failures: list[str] = []

    graph_rows: dict[str, list[KGReadiness]] = {
        "shipped": kg_readiness("shipped", args.shipped_kg, preset_readiness),
        "generated": kg_readiness("generated", args.generated_kg, preset_readiness),
    }
    for rows in graph_rows.values():
        print_kg_lines(rows, args.summary_only)

    catalog_slugs = candidate_catalog_slugs(args.candidate_exercises)
    generated_slugs = {
        row.kg_id.split(":", 1)[1]
        for row in graph_rows["generated"]
        if row.kg_id.startswith("Exercise:")
    }
    missing_from_generated = sorted(catalog_slugs - generated_slugs)

    app_ready = sum(1 for preset in preset_readiness.values() if preset.ready)
    print(
        "kg-motion-readiness summary "
        f"app_presets={len(preset_readiness)} app_guide_ready={app_ready}"
    )
    for graph_name, rows in graph_rows.items():
        summary = graph_summary(rows)
        print(
            "kg-motion-readiness summary "
            f"graph={graph_name} kg_exercises={summary['kg_exercises']} "
            f"guide_ready={summary['guide_ready']} "
            f"archetype_demo_only={summary['archetype_demo_only']} "
            f"recommend_only={summary['recommend_only']} "
            f"mapped_incomplete={summary['mapped_incomplete']}"
        )

    print(
        "kg-motion-readiness summary "
        f"candidate_catalog_exercises={len(catalog_slugs)} generated_missing={len(missing_from_generated)}"
    )
    if args.write_report:
        write_report(args.write_report, preset_readiness, graph_rows, missing_from_generated)
    for exercise_id in missing_from_generated:
        failures.append(f"candidate exercise missing from generated KG: {exercise_id}")

    if args.require_all_kg_viewer_ready:
        for preset in preset_readiness.values():
            if not preset.ready:
                failures.append(f"app preset {preset.preset_id} is not guide-ready: {','.join(preset.reasons)}")
        for graph_name, rows in graph_rows.items():
            for row in rows:
                if row.status != "guide_ready":
                    failures.append(
                        f"{graph_name} {row.kg_id} is not guide-ready: {','.join(row.reasons)}"
                    )

    if failures:
        for failure in failures:
            print(f"kg-motion-readiness failure={failure}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
