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


MAPPING_PROPERTY_KEYS = (
    "camifit_preset_id",
    "app_preset_id",
    "runtime_preset_id",
    "preset_id",
)


@dataclass(frozen=True)
class PresetReadiness:
    preset_id: str
    profile_status: str
    demo_status: str
    ready: bool
    reasons: tuple[str, ...]


@dataclass(frozen=True)
class KGReadiness:
    graph_name: str
    kg_id: str
    label: str
    mapped_preset_id: str | None
    status: str
    reasons: tuple[str, ...]


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")


def exercise_nodes(path: Path) -> list[dict[str, Any]]:
    payload = load_json(path)
    return sorted(
        (node for node in payload.get("nodes", []) if node.get("type") == "Exercise"),
        key=lambda node: str(node.get("id", "")),
    )


def candidate_catalog_slugs(path: Path) -> set[str]:
    payload = load_json(path)
    if not isinstance(payload, list):
        raise SystemExit(f"{path}: expected candidate exercise list")
    return {slug(str(item["name"])) for item in payload}


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

        readiness[preset_id] = PresetReadiness(
            preset_id=preset_id,
            profile_status=profile_status,
            demo_status="ok" if audit.ok and manifest is not None else "invalid",
            ready=not reasons,
            reasons=tuple(reasons),
        )

    return readiness


def mapped_preset_id(node: dict[str, Any], preset_ids: set[str]) -> str | None:
    properties = node.get("properties")
    if not isinstance(properties, dict):
        properties = {}

    for key in MAPPING_PROPERTY_KEYS:
        value = properties.get(key)
        if isinstance(value, str) and value:
            return value

    kg_id = str(node.get("id", ""))
    if kg_id.startswith("Exercise:"):
        kg_slug = kg_id.split(":", 1)[1]
        if kg_slug in preset_ids:
            return kg_slug

    label_slug = slug(str(node.get("label", "")))
    if label_slug in preset_ids:
        return label_slug

    return None


def kg_readiness(
    graph_name: str,
    graph_path: Path,
    preset_readiness: dict[str, PresetReadiness],
) -> list[KGReadiness]:
    preset_ids = set(preset_readiness)
    rows: list[KGReadiness] = []
    for node in exercise_nodes(graph_path):
        preset_id = mapped_preset_id(node, preset_ids)
        if preset_id is None:
            rows.append(
                KGReadiness(
                    graph_name=graph_name,
                    kg_id=str(node.get("id", "")),
                    label=str(node.get("label", "")),
                    mapped_preset_id=None,
                    status="recommend_only",
                    reasons=("no_app_preset_mapping",),
                )
            )
            continue

        preset = preset_readiness.get(preset_id)
        if preset is None:
            rows.append(
                KGReadiness(
                    graph_name=graph_name,
                    kg_id=str(node.get("id", "")),
                    label=str(node.get("label", "")),
                    mapped_preset_id=preset_id,
                    status="mapped_missing_preset",
                    reasons=("mapped_preset_not_packaged",),
                )
            )
            continue

        rows.append(
            KGReadiness(
                graph_name=graph_name,
                kg_id=str(node.get("id", "")),
                label=str(node.get("label", "")),
                mapped_preset_id=preset_id,
                status="viewer_ready" if preset.ready else "mapped_motion_incomplete",
                reasons=preset.reasons,
            )
        )
    return rows


def print_preset_lines(readiness: dict[str, PresetReadiness]) -> None:
    for preset in readiness.values():
        reason = ",".join(preset.reasons) if preset.reasons else "none"
        print(
            "kg-motion-readiness "
            f"app_preset={preset.preset_id} status={'viewer_ready' if preset.ready else 'not_ready'} "
            f"profile={preset.profile_status} demo={preset.demo_status} reasons={reason}"
        )


def print_kg_lines(rows: list[KGReadiness], summary_only: bool) -> None:
    if summary_only:
        return
    for row in rows:
        mapped = row.mapped_preset_id or "missing"
        reason = ",".join(row.reasons) if row.reasons else "none"
        print(
            "kg-motion-readiness "
            f"graph={row.graph_name} kg_id={row.kg_id} label={json.dumps(row.label)} "
            f"status={row.status} mapped_preset={mapped} reasons={reason}"
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
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    preset_readiness = readiness_for_presets(args.presets, args.profiles, args.motion_demos)
    print_preset_lines(preset_readiness)

    failures: list[str] = []
    for preset in preset_readiness.values():
        if not preset.ready:
            failures.append(f"app preset {preset.preset_id} is not viewer-ready: {','.join(preset.reasons)}")

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
        f"app_presets={len(preset_readiness)} app_viewer_ready={app_ready}"
    )
    for graph_name, rows in graph_rows.items():
        viewer_ready = sum(1 for row in rows if row.status == "viewer_ready")
        recommend_only = sum(1 for row in rows if row.status == "recommend_only")
        incomplete = len(rows) - viewer_ready - recommend_only
        print(
            "kg-motion-readiness summary "
            f"graph={graph_name} kg_exercises={len(rows)} viewer_ready={viewer_ready} "
            f"recommend_only={recommend_only} mapped_incomplete={incomplete}"
        )

    print(
        "kg-motion-readiness summary "
        f"candidate_catalog_exercises={len(catalog_slugs)} generated_missing={len(missing_from_generated)}"
    )
    for exercise_id in missing_from_generated:
        failures.append(f"candidate exercise missing from generated KG: {exercise_id}")

    if args.require_all_kg_viewer_ready:
        for graph_name, rows in graph_rows.items():
            for row in rows:
                if row.status != "viewer_ready":
                    failures.append(
                        f"{graph_name} {row.kg_id} is not viewer-ready: {','.join(row.reasons)}"
                    )

    if failures:
        for failure in failures:
            print(f"kg-motion-readiness failure={failure}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
