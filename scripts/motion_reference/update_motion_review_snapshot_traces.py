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


def trace_stats(trace: list[dict[str, Any]]) -> dict[str, int]:
    first_timestamp = int(trace[0].get("timestamp_ms", 0)) if trace else 0
    last_timestamp = int(trace[-1].get("timestamp_ms", first_timestamp)) if trace else first_timestamp
    return {
        "frameCount": len(trace),
        "durationMs": max(0, last_timestamp - first_timestamp),
        "landmarkCount": max((len(frame.get("landmarks", {})) for frame in trace), default=0),
    }


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
        updated.append(exercise_id)

    exercises = [exercise for exercise in snapshot.get("exercises", []) if isinstance(exercise, dict)]
    summary = snapshot.setdefault("summary", {})
    if isinstance(summary, dict):
        summary["playableTraces"] = sum(1 for exercise in exercises if exercise.get("trace"))
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
