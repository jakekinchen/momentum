#!/usr/bin/env python3
"""Package canonical archetype traces for the web motion-review gallery only."""

from __future__ import annotations

import argparse
import json
from datetime import UTC, date, datetime
from pathlib import Path
from typing import Any

from compile_archetype_trace import build_frames, load_profiles, summarize
from smooth_review_demo_trace import smooth_frames, trace_metrics, upsample_frames, write_frames


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PROFILES = ROOT / "scripts" / "motion_reference" / "exercise_motion_profiles.json"
DEFAULT_MOTION_DEMOS = ROOT / "Sources" / "CamiFitApp" / "Resources" / "MotionDemos"


def read_manifest(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def write_manifest(path: Path, manifest: dict[str, Any]) -> None:
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def qa_gates(existing: Any) -> list[str]:
    gates = list(existing) if isinstance(existing, list) else []
    for gate in [
        "canonical_archetype_review_demo",
        "review_gallery_motion_smoothed",
        "review_gallery_only",
        "engine_replay_candidate_only",
    ]:
        if gate not in gates:
            gates.append(gate)
    return gates


def package_trace(
    *,
    exercise_id: str,
    profile: dict[str, Any],
    output_dir: Path,
    interval_ms: int,
    upsample_factor: int,
    smooth_window: int,
    packaged_at: str,
) -> dict[str, Any]:
    output = output_dir / f"{exercise_id}.jsonl"
    manifest_path = output_dir / f"{exercise_id}.manifest.json"
    existing_manifest = read_manifest(manifest_path)

    raw_frames = build_frames(profile, interval_ms)
    smoothed_frames = smooth_frames(
        upsample_frames(raw_frames, upsample_factor),
        window=smooth_window,
        excluded_landmarks=set(),
        close_loop=True,
    )
    write_frames(output, smoothed_frames)

    archetype = str(profile["archetype"])
    manifest = {
        **existing_manifest,
        "exercise_id": exercise_id,
        "source_kind": "canonical_archetype_trace",
        "source_label": f"{archetype} canonical motion profile",
        "archetype": archetype,
        "profile_registry": "scripts/motion_reference/exercise_motion_profiles.json",
        "compiler": "scripts/motion_reference/package_review_gallery_archetype_traces.py",
        "output_trace": f"Sources/CamiFitApp/Resources/MotionDemos/{exercise_id}.jsonl",
        "playable_trace_packaged": True,
        "packaging_scope": "motion_review_gallery_demo_only",
        "review_gallery_packaged_at": packaged_at,
        "review_gallery_cleanup_at": packaged_at,
        "review_gallery_note": (
            "Canonical archetype demo packaged only so the web Motion Review mannequin "
            "and review video can be judged; this remains blocked from guide-ready and "
            "validation-ready promotion."
        ),
        "acceptance_status": existing_manifest.get("acceptance_status", "pending_reference_capture"),
        "normalizer_status": existing_manifest.get("normalizer_status", "pending_source_preserving_normalizer"),
        "interval_ms": interval_ms,
        "retarget": existing_manifest.get("retarget") or profile.get("normalizer", {}).get("retarget"),
        "required_contacts": profile.get("required_contacts", existing_manifest.get("required_contacts", [])),
        "required_output_landmarks": profile.get(
            "required_output_landmarks",
            existing_manifest.get("required_output_landmarks", []),
        ),
        "summary": summarize(smoothed_frames, archetype),
        "qa_gates": qa_gates(existing_manifest.get("qa_gates")),
        "candidate_status": "canonical_archetype_review_gallery_only",
        "replacement_plan": existing_manifest.get(
            "replacement_plan",
            "Replace with accepted first-party or licensed workout reference footage before promotion.",
        ),
        "review_gallery_motion_cleanup": {
            "status": "review_only_smoothed",
            "script": "scripts/motion_reference/package_review_gallery_archetype_traces.py",
            "upsample_factor": upsample_factor,
            "smooth_window": smooth_window,
            "excluded_landmarks": [],
            "before": trace_metrics(raw_frames),
            "after": trace_metrics(smoothed_frames),
            "promotion_scope": "no guide-ready or validation-ready promotion",
        },
        "review_gallery_detection_data": {
            "status": "generated_from_packaged_review_trace",
            "asset_script": "scripts/motion_reference/generate_motion_review_gallery_assets.py",
            "asset_path": f"website/public/motion-review-assets/{exercise_id}/mediapipe_skeleton_review.mp4",
            "promotion_scope": "review media only; not detector agreement or runtime validation",
        },
        "updated_at": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
    }
    write_manifest(manifest_path, manifest)
    return {
        "exercise_id": exercise_id,
        "frames": len(smoothed_frames),
        "output": str(output),
        "manifest": str(manifest_path),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profiles", type=Path, default=DEFAULT_PROFILES)
    parser.add_argument("--motion-demos", type=Path, default=DEFAULT_MOTION_DEMOS)
    parser.add_argument("--exercise-id", action="append", dest="exercise_ids", required=True)
    parser.add_argument("--interval-ms", type=int, default=100)
    parser.add_argument("--upsample-factor", type=int, default=4)
    parser.add_argument("--smooth-window", type=int, default=3)
    parser.add_argument("--packaged-at", default=date.today().isoformat())
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    profiles = load_profiles(args.profiles)
    results = []
    for exercise_id in args.exercise_ids:
        profile = profiles.get(exercise_id)
        if profile is None:
            raise SystemExit(f"unknown exercise id: {exercise_id}")
        results.append(
            package_trace(
                exercise_id=exercise_id,
                profile=profile,
                output_dir=args.motion_demos,
                interval_ms=args.interval_ms,
                upsample_factor=args.upsample_factor,
                smooth_window=args.smooth_window,
                packaged_at=args.packaged_at,
            )
        )
    print(json.dumps({"packaged": results}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
