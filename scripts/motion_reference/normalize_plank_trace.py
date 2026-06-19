#!/usr/bin/env python3
"""Normalize a raw MediaPipe plank hold into an app-ready demo trace."""

from __future__ import annotations

import argparse
import json
import statistics
from pathlib import Path
from typing import Any

LANDMARK_NAMES = [
    "nose",
    "left_eye_inner",
    "left_eye",
    "left_eye_outer",
    "right_eye_inner",
    "right_eye",
    "right_eye_outer",
    "left_ear",
    "right_ear",
    "mouth_left",
    "mouth_right",
    "left_shoulder",
    "right_shoulder",
    "left_elbow",
    "right_elbow",
    "left_wrist",
    "right_wrist",
    "left_pinky",
    "right_pinky",
    "left_index",
    "right_index",
    "left_thumb",
    "right_thumb",
    "left_hip",
    "right_hip",
    "left_knee",
    "right_knee",
    "left_ankle",
    "right_ankle",
    "left_heel",
    "right_heel",
    "left_foot_index",
    "right_foot_index",
]

SIDE_JOINTS = ["shoulder", "elbow", "wrist", "hip", "knee", "ankle", "heel", "foot.index"]
CONTACTS = ["primary.elbow", "secondary.elbow", "primary.foot.index", "secondary.foot.index"]


def repo_relative(path: Path | None) -> str | None:
    if path is None:
        return None
    repo_root = Path(__file__).resolve().parents[2]
    try:
        return str(path.resolve().relative_to(repo_root))
    except ValueError:
        return str(path)


def engine_name(raw_name: str) -> str:
    return raw_name.replace("_", ".")


def read_raw(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            record = json.loads(line)
            if record.get("type") != "pose":
                raise SystemExit(f"{path}:{line_number}: expected raw MediaPipe pose record")
            if record.get("poses_detected") and len(record.get("landmarks", [])) == len(LANDMARK_NAMES):
                records.append(record)
    return records


def named_landmarks(record: dict[str, Any]) -> dict[str, dict[str, float]]:
    landmarks = record.get("landmarks", [])
    mapped: dict[str, dict[str, float]] = {}
    for name, landmark in zip(LANDMARK_NAMES, landmarks):
        visibility = float(landmark.get("visibility", 0))
        mapped[engine_name(name)] = {
            "x": float(landmark["x"]),
            "y": float(landmark["y"]),
            "z": float(landmark.get("z", 0)),
            "visibility": visibility,
            "presence": float(landmark.get("presence", visibility)),
        }
    return mapped


def side_score(records: list[dict[str, Any]], side: str) -> float:
    values: list[float] = []
    for record in records:
        landmarks = named_landmarks(record)
        for joint in ("shoulder", "elbow", "hip", "knee", "ankle", "foot.index"):
            landmark = landmarks.get(f"{side}.{joint}")
            if landmark is not None:
                values.append(min(landmark["visibility"], landmark["presence"]))
    return statistics.mean(values) if values else -1


def select_primary_side(records: list[dict[str, Any]], requested: str) -> str:
    if requested != "auto":
        return requested
    left = side_score(records, "left")
    right = side_score(records, "right")
    return "left" if left >= right else "right"


def median_landmark(samples: list[dict[str, float]]) -> dict[str, float]:
    return {
        "x": statistics.median(sample["x"] for sample in samples),
        "y": statistics.median(sample["y"] for sample in samples),
        "z": statistics.median(sample["z"] for sample in samples),
        "visibility": statistics.median(sample["visibility"] for sample in samples),
        "presence": statistics.median(sample["presence"] for sample in samples),
    }


def static_median_landmarks(records: list[dict[str, Any]], primary_side: str) -> dict[str, dict[str, float]]:
    per_name: dict[str, list[dict[str, float]]] = {}
    for record in records:
        for name, landmark in named_landmarks(record).items():
            per_name.setdefault(name, []).append(landmark)

    landmarks = {
        name: median_landmark(samples)
        for name, samples in per_name.items()
        if samples
    }
    secondary_side = "right" if primary_side == "left" else "left"
    for joint in SIDE_JOINTS:
        primary = landmarks.get(f"{primary_side}.{joint}")
        secondary = landmarks.get(f"{secondary_side}.{joint}")
        if primary is not None:
            landmarks[f"primary.{joint}"] = dict(primary)
        if secondary is not None:
            landmarks[f"secondary.{joint}"] = dict(secondary)
    if "nose" in landmarks:
        landmarks["primary.nose"] = dict(landmarks["nose"])
    return landmarks


def confidence(landmark: dict[str, float]) -> float:
    return min(landmark["visibility"], landmark["presence"])


def validate_landmarks(landmarks: dict[str, dict[str, float]], min_confidence: float) -> None:
    required = [
        "primary.shoulder",
        "primary.hip",
        "primary.ankle",
        *CONTACTS,
    ]
    missing = [name for name in required if name not in landmarks]
    if missing:
        raise SystemExit(f"missing required landmarks after normalization: {missing}")
    low_confidence = [
        name
        for name in required
        if confidence(landmarks[name]) < min_confidence and not name.startswith("secondary.")
    ]
    if low_confidence:
        raise SystemExit(f"primary landmarks below confidence threshold: {low_confidence}")
    out_of_bounds = [
        name
        for name, point in landmarks.items()
        if not (0.0 <= point["x"] <= 1.0 and 0.0 <= point["y"] <= 1.0)
    ]
    if out_of_bounds:
        raise SystemExit(f"normalized landmarks out of image bounds: {out_of_bounds[:8]}")


def frame_interval(records: list[dict[str, Any]]) -> int:
    timestamps = [int(record["timestamp_ms"]) for record in records]
    intervals = [
        later - earlier
        for earlier, later in zip(timestamps, timestamps[1:])
        if later > earlier
    ]
    return round(statistics.median(intervals)) if intervals else 100


def build_frames(
    *,
    records: list[dict[str, Any]],
    landmarks: dict[str, dict[str, float]],
    exercise_id: str,
    primary_side: str,
    source_kind: str,
    frame_count: int,
    interval_ms: int,
) -> list[dict[str, Any]]:
    if not records:
        return []
    image_size = records[0].get("image_size", [1280, 720])
    source_timestamps = [int(record["timestamp_ms"]) for record in records]
    frames: list[dict[str, Any]] = []
    for index in range(frame_count):
        source_index = min(round(index * (len(records) - 1) / max(frame_count - 1, 1)), len(records) - 1)
        frames.append(
            {
                "type": "motion_demo_pose",
                "exercise_id": exercise_id,
                "timestamp_ms": index * interval_ms,
                "image_size": image_size,
                "phase": "hold",
                "primary_side": primary_side,
                "secondary_side": "right" if primary_side == "left" else "left",
                "source_kind": source_kind,
                "source_frame_id": source_index,
                "source_timestamp_ms": source_timestamps[source_index],
                "landmarks": json.loads(json.dumps(landmarks)),
            }
        )
    return frames


def write_jsonl(path: Path, frames: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for frame in frames:
            handle.write(json.dumps(frame, separators=(",", ":")) + "\n")


def write_manifest(args: argparse.Namespace, output: Path, primary_side: str, frames: list[dict[str, Any]]) -> None:
    manifest = {
        "exercise_id": args.exercise_id,
        "source_kind": args.source_kind,
        "source_label": args.source_label,
        "source_page": args.source_page,
        "source_media_url": args.source_media_url,
        "source_video": repo_relative(args.source_video),
        "source_license": args.source_license,
        "source_attribution": args.source_attribution,
        "raw_trace": repo_relative(args.raw),
        "output_trace": repo_relative(output),
        "normalizer": "scripts/motion_reference/normalize_plank_trace.py",
        "retarget": "static_median_external_reference_hold",
        "primary_side": primary_side,
        "frame_count": len(frames),
        "source_frame_start": frames[0]["source_frame_id"] if frames else None,
        "source_frame_end": frames[-1]["source_frame_id"] if frames else None,
        "source_timestamp_start_ms": frames[0]["source_timestamp_ms"] if frames else None,
        "source_timestamp_end_ms": frames[-1]["source_timestamp_ms"] if frames else None,
        "contact_policy": "median_pin_forearms_and_toes",
        "qa_gates": [
            "source_clip_reviewed",
            "full_body_primary_side_visible",
            "static_median_hold_pose",
            "contact_locked",
            "body_line_stable",
            "engine_accepts_hold",
            "viewer_reviewed",
        ],
        "viewer_command": (
            f"cp {repo_relative(output)} "
            f"Sources/CamiFitApp/Resources/MotionDemos/{args.exercise_id}.jsonl && "
            f"CAMIFIT_GUIDE_EXERCISE={args.exercise_id} ./script/build_and_run.sh --verify"
        ),
    }
    output.with_suffix(".manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--exercise-id", default="bodyweight_plank")
    parser.add_argument("--primary-side", choices=["auto", "left", "right"], default="auto")
    parser.add_argument("--frame-count", type=int, default=31)
    parser.add_argument("--min-confidence", type=float, default=0.65)
    parser.add_argument("--source-kind", default="licensed_external_reference_trace")
    parser.add_argument("--source-label", required=True)
    parser.add_argument("--source-page", required=True)
    parser.add_argument("--source-media-url", required=True)
    parser.add_argument("--source-video", type=Path)
    parser.add_argument("--source-license", required=True)
    parser.add_argument("--source-attribution", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    records = read_raw(args.raw)
    if not records:
        raise SystemExit(f"{args.raw}: no usable pose records")

    primary_side = select_primary_side(records, args.primary_side)
    landmarks = static_median_landmarks(records, primary_side)
    validate_landmarks(landmarks, args.min_confidence)
    interval_ms = frame_interval(records)
    frames = build_frames(
        records=records,
        landmarks=landmarks,
        exercise_id=args.exercise_id,
        primary_side=primary_side,
        source_kind=args.source_kind,
        frame_count=args.frame_count,
        interval_ms=interval_ms,
    )
    write_jsonl(args.output, frames)
    write_manifest(args, args.output, primary_side, frames)

    print(
        f"motion-reference normalized={args.output} frames={len(frames)} "
        f"primary_side={primary_side} interval_ms={interval_ms}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
