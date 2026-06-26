#!/usr/bin/env python3
"""Refresh embedded trace frames in the motion-review website snapshot."""

from __future__ import annotations

import argparse
import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MOTION_DEMOS = ROOT / "Sources" / "CamiFitApp" / "Resources" / "MotionDemos"
DEFAULT_SNAPSHOT = ROOT / "website" / "src" / "data" / "motionReviewSnapshot.json"
PROMOTION_TIERS = [
    "recommendation-only",
    "source-candidate",
    "detector-reviewable",
    "avatar-demo-candidate",
    "guide-ready",
    "validation-ready",
]


def read_trace(path: Path) -> list[dict[str, Any]]:
    frames: list[dict[str, Any]] = []
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            frame = json.loads(line)
            landmarks = frame.get("landmarks")
            if not isinstance(landmarks, dict):
                raise SystemExit(f"{path}:{line_number}: missing landmarks")
            output: dict[str, Any] = {"landmarks": landmarks}
            for key in ("frame_id", "timestamp_ms", "image_size"):
                if key in frame:
                    output[key] = frame[key]
            frames.append(output)
    return frames


def read_manifest(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    payload = json.loads(path.read_text(encoding="utf-8"))
    return payload if isinstance(payload, dict) else None


def trace_stats(trace: list[dict[str, Any]]) -> dict[str, int]:
    first_timestamp = int(trace[0].get("timestamp_ms", 0)) if trace else 0
    last_timestamp = int(trace[-1].get("timestamp_ms", first_timestamp)) if trace else first_timestamp
    return {
        "frameCount": len(trace),
        "durationMs": max(0, last_timestamp - first_timestamp),
        "landmarkCount": max((len(frame.get("landmarks", {})) for frame in trace), default=0),
    }


def next_review_for_exercise(exercise: dict[str, Any]) -> str:
    has_trace = bool(exercise.get("trace"))
    media = exercise.get("media") if isinstance(exercise.get("media"), dict) else {}
    has_detector_video = bool(media.get("detectorVideoUrl"))
    gate_status = str(exercise.get("gateStatus") or "")
    acceptance_status = str(exercise.get("acceptanceStatus") or "")

    if not has_trace:
        return "Capture or normalize a playable JSONL trace before judging the app motion."
    if not has_detector_video:
        return "Generate a review video so the trace can be checked on the gallery surface."
    if gate_status == "reference_capture_required":
        return "Review the trace media, then either promote after strict provenance or keep recommendation-only."
    if "accepted" not in acceptance_status.lower():
        return "Reconcile the manifest acceptance status before release claims."
    return "Phone-review the 3D loop and detector clip for anatomy, phase, contact, and rep-count consistency."


def missing_items_for_exercise(exercise: dict[str, Any], manifest: dict[str, Any] | None) -> list[str]:
    missing: list[str] = []
    media = exercise.get("media") if isinstance(exercise.get("media"), dict) else {}

    if not exercise.get("trace"):
        missing.append("playable JSONL")
    if manifest is None:
        missing.append("motion manifest")
    if not media.get("detectorVideoUrl"):
        missing.append("review video")
    if not media.get("contactSheetUrl"):
        missing.append("review contact sheet")
    if not media.get("sourceVideoUrl"):
        missing.append("local source video artifact")
    if exercise.get("gateStatus") == "reference_capture_required":
        missing.append("guide-ready promotion")

    return missing


def reconcile_factory_readiness(exercise: dict[str, Any], missing: list[str], next_review: str) -> None:
    factory = exercise.get("factory")
    if not isinstance(factory, dict):
        return

    has_trace = bool(exercise.get("trace"))
    guide_blockers = factory.get("guideReadyBlockers")
    guide_blockers = guide_blockers if isinstance(guide_blockers, list) else []
    validation_blockers = factory.get("validationReadyBlockers")
    validation_blockers = validation_blockers if isinstance(validation_blockers, list) else []

    current_signals = factory.setdefault("currentSignals", {})
    if isinstance(current_signals, dict):
        current_signals["playableJsonl"] = has_trace

    factory["warnings"] = missing
    factory["nextAction"] = next_review

    if factory.get("validationReady") is True:
        tier = "validation-ready"
    elif factory.get("guideReady") is True and not guide_blockers:
        tier = "guide-ready"
    elif has_trace:
        tier = "avatar-demo-candidate"
    else:
        tier = str(factory.get("promotionTier") or "recommendation-only")

    factory["promotionTier"] = tier
    factory["tierIndex"] = PROMOTION_TIERS.index(tier) if tier in PROMOTION_TIERS else 0
    factory["guideReady"] = tier == "guide-ready" and not guide_blockers
    factory["validationReady"] = tier == "validation-ready" and not validation_blockers


def reconcile_exercise_state(exercise: dict[str, Any], manifest: dict[str, Any] | None) -> None:
    missing = missing_items_for_exercise(exercise, manifest)
    next_review = next_review_for_exercise(exercise)
    exercise["missing"] = missing
    exercise["nextReview"] = next_review
    reconcile_factory_readiness(exercise, missing, next_review)


def refresh_summary(snapshot: dict[str, Any]) -> None:
    exercises = [exercise for exercise in snapshot.get("exercises", []) if isinstance(exercise, dict)]
    summary = snapshot.setdefault("summary", {})
    if not isinstance(summary, dict):
        return

    summary["playableTraces"] = sum(1 for exercise in exercises if exercise.get("trace"))
    summary["guideReady"] = sum(
        1 for exercise in exercises if isinstance(exercise.get("factory"), dict) and exercise["factory"].get("guideReady")
    )
    summary["validationReady"] = sum(
        1
        for exercise in exercises
        if isinstance(exercise.get("factory"), dict) and exercise["factory"].get("validationReady")
    )
    summary["blockedFromGuideReady"] = sum(
        1
        for exercise in exercises
        if isinstance(exercise.get("factory"), dict) and exercise["factory"].get("guideReadyBlockers")
    )
    tier_counts = {tier: 0 for tier in PROMOTION_TIERS}
    for exercise in exercises:
        factory = exercise.get("factory")
        tier = factory.get("promotionTier") if isinstance(factory, dict) else None
        if isinstance(tier, str) and tier in tier_counts:
            tier_counts[tier] += 1
    summary["tierCounts"] = tier_counts


def update_snapshot(snapshot: dict[str, Any], motion_demos: Path, exercise_ids: set[str]) -> list[str]:
    by_id = {
        exercise.get("id"): exercise
        for exercise in snapshot.get("exercises", [])
        if isinstance(exercise, dict) and isinstance(exercise.get("id"), str)
    }
    updated: list[str] = []
    for exercise_id in sorted(exercise_ids):
        trace_path = motion_demos / f"{exercise_id}.jsonl"
        exercise = by_id.get(exercise_id)
        if exercise is None or not trace_path.exists():
            continue
        trace = read_trace(trace_path)
        exercise["trace"] = trace
        exercise.update(trace_stats(trace))
        reconcile_exercise_state(exercise, read_manifest(motion_demos / f"{exercise_id}.manifest.json"))
        updated.append(exercise_id)

    refresh_summary(snapshot)
    snapshot["generatedAt"] = datetime.now(UTC).isoformat().replace("+00:00", "Z")
    return updated


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--motion-demos", type=Path, default=DEFAULT_MOTION_DEMOS)
    parser.add_argument("--snapshot", type=Path, default=DEFAULT_SNAPSHOT)
    parser.add_argument("--exercise-id", action="append", dest="exercise_ids")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    snapshot = json.loads(args.snapshot.read_text(encoding="utf-8"))
    exercise_ids = set(args.exercise_ids or [path.stem for path in args.motion_demos.glob("*.jsonl")])
    updated = update_snapshot(snapshot, args.motion_demos, exercise_ids)
    args.snapshot.write_text(json.dumps(snapshot, indent=2) + "\n", encoding="utf-8")
    print(f"motion-review snapshot traces updated={len(updated)} ids={','.join(updated)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
