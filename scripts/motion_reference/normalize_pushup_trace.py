#!/usr/bin/env python3
"""Normalize a raw MediaPipe push-up capture into app-ready demo landmarks."""

from __future__ import annotations

import argparse
import json
import statistics
from pathlib import Path
from typing import Any

LANDMARK_NAMES = [
    "nose",
    "left.eye.inner",
    "left.eye",
    "left.eye.outer",
    "right.eye.inner",
    "right.eye",
    "right.eye.outer",
    "left.ear",
    "right.ear",
    "mouth.left",
    "mouth.right",
    "left.shoulder",
    "right.shoulder",
    "left.elbow",
    "right.elbow",
    "left.wrist",
    "right.wrist",
    "left.pinky",
    "right.pinky",
    "left.index",
    "right.index",
    "left.thumb",
    "right.thumb",
    "left.hip",
    "right.hip",
    "left.knee",
    "right.knee",
    "left.ankle",
    "right.ankle",
    "left.heel",
    "right.heel",
    "left.foot.index",
    "right.foot.index",
]

PRIMARY_JOINTS = ["shoulder", "elbow", "wrist", "hip", "knee", "ankle", "heel", "foot.index"]
CONTACT_JOINTS = {"wrist", "heel", "foot.index"}


def read_raw(path: Path) -> list[dict[str, Any]]:
    rows = []
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def landmark_dict(row: dict[str, Any]) -> dict[str, dict[str, float]]:
    landmarks = row.get("landmarks") or []
    if len(landmarks) != len(LANDMARK_NAMES):
        return {}
    return {name: normalize_landmark(landmarks[index]) for index, name in enumerate(LANDMARK_NAMES)}


def normalize_landmark(raw: dict[str, Any]) -> dict[str, float]:
    visibility = float(raw.get("visibility", 1))
    return {
        "x": float(raw["x"]),
        "y": float(raw["y"]),
        "z": float(raw.get("z", 0)),
        "visibility": visibility,
        "presence": float(raw.get("presence", visibility)),
    }


def strongest_side(rows: list[dict[str, Any]]) -> str:
    scores: dict[str, float] = {}
    for side in ("left", "right"):
        values = []
        for row in rows:
            landmarks = landmark_dict(row)
            for joint in PRIMARY_JOINTS:
                landmark = landmarks.get(f"{side}.{joint}")
                if landmark:
                    values.append(landmark["visibility"])
        scores[side] = statistics.mean(values) if values else -1
    return "right" if scores["right"] > scores["left"] else "left"


def contact_medians(frames: list[dict[str, Any]]) -> dict[str, dict[str, float]]:
    medians: dict[str, dict[str, float]] = {}
    for name in [f"primary.{joint}" for joint in CONTACT_JOINTS]:
        values = {axis: [] for axis in ("x", "y", "z")}
        confidence = []
        for frame in frames:
            landmark = frame["landmarks"].get(name)
            if not landmark:
                continue
            if landmark["visibility"] < 0.50:
                continue
            for axis in values:
                values[axis].append(landmark[axis])
            confidence.append(landmark["visibility"])
        if all(values[axis] for axis in values):
            medians[name] = {
                "x": statistics.median(values["x"]),
                "y": statistics.median(values["y"]),
                "z": statistics.median(values["z"]),
                "visibility": statistics.median(confidence),
                "presence": statistics.median(confidence),
            }
    return medians


def smooth_frames(frames: list[dict[str, Any]], window: int) -> list[dict[str, Any]]:
    if window <= 1 or len(frames) < 3:
        return frames
    radius = window // 2
    smoothed: list[dict[str, Any]] = []
    names = sorted({name for frame in frames for name in frame["landmarks"]})

    for index, frame in enumerate(frames):
        landmarks: dict[str, dict[str, float]] = {}
        for name in names:
            if joint_name(name) in CONTACT_JOINTS:
                if name in frame["landmarks"]:
                    landmarks[name] = dict(frame["landmarks"][name])
                continue
            neighbors = [
                frames[i]["landmarks"][name]
                for i in range(max(0, index - radius), min(len(frames), index + radius + 1))
                if name in frames[i]["landmarks"]
            ]
            if not neighbors:
                continue
            weights = [max(0.05, item.get("visibility", 1)) for item in neighbors]
            total = sum(weights)
            landmarks[name] = {
                axis: sum(item[axis] * weight for item, weight in zip(neighbors, weights)) / total
                for axis in ("x", "y", "z", "visibility", "presence")
            }
        smoothed.append({**frame, "landmarks": landmarks})
    return smoothed


def joint_name(name: str) -> str:
    for prefix in ("primary.", "secondary."):
        if name.startswith(prefix):
            return name[len(prefix) :]
    return name


def add_synthetic_secondary(landmarks: dict[str, dict[str, float]], z_offset: float) -> None:
    for joint in PRIMARY_JOINTS:
        primary_name = f"primary.{joint}"
        source = landmarks.get(primary_name)
        if not source:
            continue
        secondary = dict(source)
        secondary["z"] = source["z"] + z_offset
        secondary["visibility"] = min(source["visibility"], 0.88)
        secondary["presence"] = min(source["presence"], 0.88)
        landmarks[f"secondary.{joint}"] = secondary


def build_frames(
    *,
    rows: list[dict[str, Any]],
    primary_side: str,
    z_offset: float,
    smooth_window: int,
) -> list[dict[str, Any]]:
    if not rows:
        return []
    start_ms = int(rows[0]["timestamp_ms"])
    frames = []

    for row in rows:
        raw_landmarks = landmark_dict(row)
        if not raw_landmarks:
            continue
        landmarks: dict[str, dict[str, float]] = {}

        if "nose" in raw_landmarks:
            landmarks["nose"] = raw_landmarks["nose"]
            landmarks["primary.nose"] = raw_landmarks["nose"]

        for joint in PRIMARY_JOINTS:
            source = raw_landmarks.get(f"{primary_side}.{joint}")
            if source:
                landmarks[f"primary.{joint}"] = source

        frame = {
            "type": "motion_demo_pose",
            "frame_id": len(frames),
            "timestamp_ms": int(row["timestamp_ms"]) - start_ms,
            "image_size": row.get("image_size", [1080, 1920]),
            "landmarks": landmarks,
        }
        frames.append(frame)

    frames = smooth_frames(frames, smooth_window)

    medians = contact_medians(frames)
    for frame in frames:
        for name, pinned in medians.items():
            if name in frame["landmarks"]:
                frame["landmarks"][name] = dict(pinned)
        add_synthetic_secondary(frame["landmarks"], z_offset)

    return frames


def close_loop(frames: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if len(frames) < 2:
        return frames
    deltas = [
        frames[index]["timestamp_ms"] - frames[index - 1]["timestamp_ms"]
        for index in range(1, len(frames))
        if frames[index]["timestamp_ms"] > frames[index - 1]["timestamp_ms"]
    ]
    interval = int(statistics.median(deltas)) if deltas else 67
    closing = json.loads(json.dumps(frames[0]))
    closing["frame_id"] = len(frames)
    closing["timestamp_ms"] = frames[-1]["timestamp_ms"] + interval
    return frames + [closing]


def mirror_frames_x(frames: list[dict[str, Any]]) -> list[dict[str, Any]]:
    mirrored = json.loads(json.dumps(frames))
    for frame in mirrored:
        for landmark in frame["landmarks"].values():
            landmark["x"] = 1.0 - landmark["x"]
    return mirrored


def write_manifest(args: argparse.Namespace, output: Path, primary_side: str, frame_count: int) -> None:
    manifest = {
        "exercise_id": args.exercise_id,
        "source_kind": "trainer_reference_trace",
        "source_label": f"first-party webcam push-up capture; primary_side={primary_side}",
        "source_video": str(args.video) if args.video else None,
        "raw_trace": str(args.raw),
        "normalizer": "scripts/motion_reference/normalize_pushup_trace.py",
        "cycle_start_index": args.cycle_start_index,
        "cycle_end_index": args.cycle_end_index,
        "contact_policy": "pin_primary_wrist_heel_toe",
        "secondary_policy": "synthetic_depth_offset_from_primary",
        "smooth_window": args.smooth_window,
        "mirror_x": args.mirror_x,
        "frame_count": frame_count,
    }
    output.with_suffix(".manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--video", type=Path)
    parser.add_argument("--exercise-id", default="bodyweight_pushup")
    parser.add_argument("--primary-side", choices=["auto", "left", "right"], default="auto")
    parser.add_argument("--cycle-start-index", type=int)
    parser.add_argument("--cycle-end-index", type=int)
    parser.add_argument("--smooth-window", type=int, default=5)
    parser.add_argument("--secondary-z-offset", type=float, default=0.12)
    parser.add_argument("--close-loop", action="store_true")
    parser.add_argument("--mirror-x", action="store_true", help="Mirror output landmarks horizontally so the guide faces right.")
    return parser.parse_args()


def main() -> int:
    global args
    args = parse_args()
    rows = read_raw(args.raw)
    if args.cycle_start_index is not None or args.cycle_end_index is not None:
        start = args.cycle_start_index or 0
        end = args.cycle_end_index if args.cycle_end_index is not None else len(rows) - 1
        rows = rows[start : end + 1]
    primary_side = strongest_side(rows) if args.primary_side == "auto" else args.primary_side
    frames = build_frames(
        rows=rows,
        primary_side=primary_side,
        z_offset=args.secondary_z_offset,
        smooth_window=args.smooth_window,
    )
    if args.close_loop:
        frames = close_loop(frames)
    if args.mirror_x:
        frames = mirror_frames_x(frames)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as handle:
        for frame in frames:
            handle.write(json.dumps(frame, separators=(",", ":")) + "\n")
    write_manifest(args, args.output, primary_side, len(frames))
    print(f"motion-reference normalized={args.output} frames={len(frames)} primary_side={primary_side}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
