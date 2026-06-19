#!/usr/bin/env python3
"""Normalize a raw MediaPipe plank-to-pike clip into app-ready demo landmarks."""

from __future__ import annotations

import argparse
import copy
import json
import math
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
DEFAULT_CONTACTS = ["primary.wrist", "primary.foot.index"]
REQUIRED = [
    "primary.shoulder",
    "primary.elbow",
    "primary.wrist",
    "primary.hip",
    "primary.knee",
    "primary.ankle",
]


def raw_name_to_engine_name(name: str) -> str:
    return name.replace("_", ".")


def stable_path(path: Path | None) -> str | None:
    if path is None:
        return None
    try:
        return str(path.relative_to(Path.cwd()))
    except ValueError:
        return str(path)


def load_raw_records(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            record = json.loads(line)
            if record.get("type") != "pose":
                raise SystemExit(f"{path}:{line_number}: expected raw MediaPipe type 'pose'")
            if record.get("poses_detected") and len(record.get("landmarks", [])) == len(LANDMARK_NAMES):
                records.append(record)
    return records


def named_landmarks(record: dict[str, Any]) -> dict[str, dict[str, float]]:
    mapped: dict[str, dict[str, float]] = {}
    for name, landmark in zip(LANDMARK_NAMES, record.get("landmarks", [])):
        visibility = float(landmark.get("visibility", 0))
        mapped[raw_name_to_engine_name(name)] = {
            "x": float(landmark["x"]),
            "y": float(landmark["y"]),
            "z": float(landmark.get("z", 0)),
            "visibility": visibility,
            "presence": float(landmark.get("presence", visibility)),
        }
    return mapped


def confidence(landmark: dict[str, float]) -> float:
    return min(float(landmark.get("visibility", 0)), float(landmark.get("presence", 0)))


def angle_degrees(a: dict[str, float], b: dict[str, float], c: dict[str, float]) -> float:
    bax = a["x"] - b["x"]
    bay = a["y"] - b["y"]
    bcx = c["x"] - b["x"]
    bcy = c["y"] - b["y"]
    dot = (bax * bcx) + (bay * bcy)
    norm_a = max(math.hypot(bax, bay), 1e-9)
    norm_c = max(math.hypot(bcx, bcy), 1e-9)
    return math.degrees(math.acos(max(-1.0, min(1.0, dot / (norm_a * norm_c)))))


def shoulder_stack_degrees(frame: dict[str, Any]) -> float:
    landmarks = frame["landmarks"]
    shoulder = landmarks["primary.shoulder"]
    wrist = landmarks["primary.wrist"]
    return math.degrees(math.atan2(abs(wrist["x"] - shoulder["x"]), abs(wrist["y"] - shoulder["y"])))


def pike_angle(frame: dict[str, Any]) -> float:
    landmarks = frame["landmarks"]
    return angle_degrees(
        landmarks["primary.shoulder"],
        landmarks["primary.hip"],
        landmarks["primary.ankle"],
    )


def knee_angle(frame: dict[str, Any]) -> float:
    landmarks = frame["landmarks"]
    return angle_degrees(
        landmarks["primary.hip"],
        landmarks["primary.knee"],
        landmarks["primary.ankle"],
    )


def elbow_angle(frame: dict[str, Any]) -> float:
    landmarks = frame["landmarks"]
    return angle_degrees(
        landmarks["primary.shoulder"],
        landmarks["primary.elbow"],
        landmarks["primary.wrist"],
    )


def side_score(records: list[dict[str, Any]], side: str) -> float:
    values: list[float] = []
    for record in records:
        landmarks = named_landmarks(record)
        for joint in ("shoulder", "elbow", "wrist", "hip", "knee", "ankle", "foot.index"):
            landmark = landmarks.get(f"{side}.{joint}")
            if landmark is not None:
                values.append(confidence(landmark))
    return statistics.mean(values) if values else -1


def select_primary_side(records: list[dict[str, Any]], requested: str) -> str:
    if requested != "auto":
        return requested
    left = side_score(records, "left")
    right = side_score(records, "right")
    return "left" if left >= right else "right"


def build_motion_frames(args: argparse.Namespace, records: list[dict[str, Any]], primary_side: str) -> list[dict[str, Any]]:
    secondary_side = "left" if primary_side == "right" else "right"
    frames: list[dict[str, Any]] = []
    for source_frame_index, record in enumerate(records):
        mapped = named_landmarks(record)
        if not mapped:
            continue

        landmarks = copy.deepcopy(mapped)
        for joint in SIDE_JOINTS:
            primary = mapped.get(f"{primary_side}.{joint}")
            secondary = mapped.get(f"{secondary_side}.{joint}")
            if primary is not None:
                landmarks[f"primary.{joint}"] = dict(primary)
            if secondary is not None:
                landmarks[f"secondary.{joint}"] = dict(secondary)
        if "nose" in mapped:
            landmarks["primary.nose"] = dict(mapped["nose"])

        source_timestamp = int(record["timestamp_ms"])
        frames.append(
            {
                "type": "motion_demo_pose",
                "exercise_id": args.exercise_id,
                "timestamp_ms": source_timestamp,
                "image_size": record.get("image_size", [1280, 720]),
                "phase": "raw_plank_to_pike",
                "primary_side": primary_side,
                "secondary_side": secondary_side,
                "source_kind": args.source_kind,
                "source_frame_id": source_frame_index,
                "source_timestamp_ms": source_timestamp + args.source_start_ms,
                "landmarks": landmarks,
            }
        )
    return frames


def frame_interval_ms(frames: list[dict[str, Any]]) -> int:
    intervals = [
        later["timestamp_ms"] - earlier["timestamp_ms"]
        for earlier, later in zip(frames, frames[1:])
        if later["timestamp_ms"] > earlier["timestamp_ms"]
    ]
    return max(1, round(statistics.median(intervals))) if intervals else 100


def relabel_timestamps(frames: list[dict[str, Any]], interval_ms: int) -> list[dict[str, Any]]:
    output = [copy.deepcopy(frame) for frame in frames]
    for index, frame in enumerate(output):
        frame["timestamp_ms"] = index * interval_ms
    return output


def descent_mirror_cycle(args: argparse.Namespace, frames: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if not frames:
        return []
    if args.cycle_bottom_index is None:
        bottom_index = min(range(len(frames)), key=lambda index: pike_angle(frames[index]))
    else:
        bottom_index = args.cycle_bottom_index
    if args.cycle_start_index is None:
        start_index = max(range(0, bottom_index + 1), key=lambda index: pike_angle(frames[index]))
    else:
        start_index = args.cycle_start_index
    if start_index < 0 or start_index >= bottom_index or bottom_index >= len(frames):
        raise SystemExit("--cycle-start-index must be before a valid --cycle-bottom-index")

    descent = frames[start_index : bottom_index + 1]
    top_pad = [copy.deepcopy(descent[0]) for _ in range(args.top_pad_frames)]
    cycle = top_pad + descent + list(reversed(descent[:-1])) + copy.deepcopy(top_pad)
    for frame in cycle:
        frame["phase"] = "source_plank_to_pike_mirrored_cycle"
    return relabel_timestamps(cycle, frame_interval_ms(descent))


def smooth_frames(frames: list[dict[str, Any]], alpha: float, exclude: set[str]) -> None:
    previous: dict[str, dict[str, float]] = {}
    for frame in frames:
        landmarks = frame["landmarks"]
        for name, landmark in list(landmarks.items()):
            if name in exclude or name not in previous:
                previous[name] = dict(landmark)
                continue
            smoothed = dict(landmark)
            for axis in ("x", "y", "z"):
                smoothed[axis] = (alpha * landmark[axis]) + ((1 - alpha) * previous[name][axis])
            landmarks[name] = smoothed
            previous[name] = dict(smoothed)


def anchor_contacts(frames: list[dict[str, Any]], anchors: list[str], min_confidence: float) -> dict[str, dict[str, float]]:
    solved: dict[str, dict[str, float]] = {}
    for anchor in anchors:
        samples = [
            frame["landmarks"][anchor]
            for frame in frames
            if anchor in frame["landmarks"] and confidence(frame["landmarks"][anchor]) >= min_confidence
        ]
        if not samples:
            continue
        solved[anchor] = {
            "x": statistics.median(sample["x"] for sample in samples),
            "y": statistics.median(sample["y"] for sample in samples),
            "z": statistics.median(sample["z"] for sample in samples),
        }

    for frame in frames:
        for anchor, fixed in solved.items():
            if anchor not in frame["landmarks"]:
                continue
            frame["landmarks"][anchor]["x"] = fixed["x"]
            frame["landmarks"][anchor]["y"] = fixed["y"]
            frame["landmarks"][anchor]["z"] = fixed["z"]
    return solved


def fit_viewport(
    frames: list[dict[str, Any]],
    *,
    target_x_min: float = 0.14,
    target_x_max: float = 0.86,
    target_y_min: float = 0.12,
    target_y_max: float = 0.88,
) -> None:
    samples: list[dict[str, float]] = []
    for frame in frames:
        for point in frame.get("landmarks", {}).values():
            if isinstance(point, dict) and confidence(point) >= 0.35:
                samples.append(point)
    if not samples:
        return

    source_x_min = min(point["x"] for point in samples)
    source_x_max = max(point["x"] for point in samples)
    source_y_min = min(point["y"] for point in samples)
    source_y_max = max(point["y"] for point in samples)
    source_width = max(source_x_max - source_x_min, 1e-6)
    source_height = max(source_y_max - source_y_min, 1e-6)
    scale = min((target_x_max - target_x_min) / source_width, (target_y_max - target_y_min) / source_height)
    fitted_width = source_width * scale
    fitted_height = source_height * scale
    x_offset = target_x_min + (((target_x_max - target_x_min) - fitted_width) / 2)
    y_offset = target_y_min + (((target_y_max - target_y_min) - fitted_height) / 2)

    for frame in frames:
        for point in frame.get("landmarks", {}).values():
            if not isinstance(point, dict):
                continue
            point["x"] = x_offset + ((point["x"] - source_x_min) * scale)
            point["y"] = y_offset + ((point["y"] - source_y_min) * scale)


def close_loop(frames: list[dict[str, Any]]) -> None:
    if len(frames) < 2:
        return
    first_landmarks = frames[0].get("landmarks", {})
    last_landmarks = frames[-1].get("landmarks", {})
    for name, first_point in first_landmarks.items():
        if name not in last_landmarks:
            continue
        for axis in ("x", "y", "z"):
            last_landmarks[name][axis] = first_point[axis]


def validate_frames(frames: list[dict[str, Any]], min_confidence: float) -> None:
    if not frames:
        raise SystemExit("no usable pike frames")
    missing = [
        name
        for name in REQUIRED + DEFAULT_CONTACTS
        if any(name not in frame["landmarks"] for frame in frames)
    ]
    if missing:
        raise SystemExit(f"missing required pike landmarks: {sorted(set(missing))}")
    low_confidence = [
        name
        for name in REQUIRED
        if min(confidence(frame["landmarks"][name]) for frame in frames) < min_confidence
    ]
    if low_confidence:
        raise SystemExit(f"primary landmarks below confidence threshold: {low_confidence}")
    out_of_bounds = [
        f"frame={frame_index}:{name}:x={point['x']:.3f}:y={point['y']:.3f}"
        for frame_index, frame in enumerate(frames)
        for name, point in frame["landmarks"].items()
        if not (0.0 <= point["x"] <= 1.0 and 0.0 <= point["y"] <= 1.0)
    ]
    if out_of_bounds:
        raise SystemExit(f"normalized landmarks out of image bounds: {out_of_bounds[:8]}")


def trace_summary(frames: list[dict[str, Any]]) -> dict[str, Any]:
    pikes = [pike_angle(frame) for frame in frames]
    knees = [knee_angle(frame) for frame in frames]
    elbows = [elbow_angle(frame) for frame in frames]
    stacks = [shoulder_stack_degrees(frame) for frame in frames]
    return {
        "frames": len(frames),
        "min_primary_pike_angle": round(min(pikes), 2),
        "max_primary_pike_angle": round(max(pikes), 2),
        "min_primary_knee_angle": round(min(knees), 2),
        "min_primary_elbow_angle": round(min(elbows), 2),
        "max_primary_shoulder_stack_angle": round(max(stacks), 2),
    }


def write_outputs(args: argparse.Namespace, frames: list[dict[str, Any]], solved_contacts: dict[str, dict[str, float]]) -> None:
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as handle:
        for frame in frames:
            handle.write(json.dumps(frame, separators=(",", ":")) + "\n")

    manifest = {
        "exercise_id": args.exercise_id,
        "source_kind": args.source_kind,
        "source_label": args.source_label,
        "source_page": args.source_page,
        "source_media_url": args.source_media_url,
        "source_video": stable_path(args.source_video),
        "source_license": args.source_license,
        "source_attribution": args.source_attribution,
        "raw_trace": stable_path(args.raw),
        "output_trace": stable_path(args.output),
        "normalizer": "scripts/motion_reference/normalize_pike_trace.py",
        "retarget": "raw_mediapipe_side_view_with_planted_contact_lock",
        "cycle_mode": "descent-mirror",
        "cycle_start_index": args.cycle_start_index,
        "cycle_bottom_index": args.cycle_bottom_index,
        "top_pad_frames": args.top_pad_frames,
        "primary_side": frames[0].get("primary_side"),
        "anchor_landmarks": sorted(solved_contacts),
        "fit_viewport": args.fit_viewport,
        "summary": trace_summary(frames),
        "qa_gates": [
            "licensed_source_recorded",
            "raw_pose_reviewed",
            "high_plank_to_pike_source_segment",
            "contact_locked",
            "descent_mirrored_to_closed_cycle",
            "knees_and_elbows_stay_long",
            "engine_counts_one_rep",
            "viewer_reviewed",
        ],
        "viewer_command": (
            "cp "
            + stable_path(args.output)
            + " Sources/CamiFitApp/Resources/MotionDemos/"
            + args.exercise_id
            + ".jsonl && CAMIFIT_GUIDE_EXERCISE="
            + args.exercise_id
            + " ./script/build_and_run.sh --verify"
        ),
    }
    args.output.with_suffix(".manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n",
        encoding="utf-8",
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--exercise-id", default="bodyweight_pike")
    parser.add_argument("--primary-side", choices=["left", "right", "auto"], default="auto")
    parser.add_argument("--smooth-alpha", type=float, default=0.65)
    parser.add_argument("--min-confidence", type=float, default=0.60)
    parser.add_argument("--cycle-start-index", type=int)
    parser.add_argument("--cycle-bottom-index", type=int)
    parser.add_argument("--top-pad-frames", type=int, default=0)
    parser.add_argument("--anchors", default=",".join(DEFAULT_CONTACTS))
    parser.add_argument("--fit-viewport", action="store_true")
    parser.add_argument("--source-start-ms", type=int, default=0)
    parser.add_argument("--source-kind", default="licensed_external_reference_trace")
    parser.add_argument("--source-label")
    parser.add_argument("--source-page")
    parser.add_argument("--source-media-url")
    parser.add_argument("--source-video", type=Path)
    parser.add_argument("--source-license")
    parser.add_argument("--source-attribution")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    args.raw = args.raw.expanduser().resolve()
    args.output = args.output.expanduser().resolve()
    if args.source_video is not None:
        args.source_video = args.source_video.expanduser().resolve()

    records = load_raw_records(args.raw)
    if not records:
        raise SystemExit("raw trace contains no detected poses")
    primary_side = select_primary_side(records, args.primary_side)
    frames = build_motion_frames(args, records, primary_side)
    frames = descent_mirror_cycle(args, frames)
    if args.fit_viewport:
        fit_viewport(frames)
    anchors = {name.strip() for name in args.anchors.split(",") if name.strip()}
    smooth_frames(frames, args.smooth_alpha, exclude=anchors)
    solved_contacts = anchor_contacts(frames, sorted(anchors), args.min_confidence)
    close_loop(frames)
    validate_frames(frames, args.min_confidence)
    write_outputs(args, frames, solved_contacts)

    summary = trace_summary(frames)
    print(
        "motion-reference normalized="
        f"{args.output} frames={summary['frames']} "
        f"primary_pike={summary['min_primary_pike_angle']}..{summary['max_primary_pike_angle']} "
        f"knee_min={summary['min_primary_knee_angle']} elbow_min={summary['min_primary_elbow_angle']} "
        f"anchors={','.join(sorted(solved_contacts))}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
