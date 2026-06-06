#!/usr/bin/env python3
"""Normalize a raw MediaPipe lunge trace into app-ready demo landmarks."""

from __future__ import annotations

import argparse
import copy
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
DEFAULT_ANCHORS = [
    "primary.ankle",
    "primary.heel",
    "primary.foot.index",
    "secondary.foot.index",
]


def raw_name_to_engine_name(name: str) -> str:
    return name.replace("_", ".")


def load_raw_records(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            record = json.loads(line)
            if record.get("type") != "pose":
                raise SystemExit(f"{path}:{line_number}: expected raw MediaPipe type 'pose'")
            records.append(record)
    return records


def named_landmarks(record: dict[str, Any]) -> dict[str, dict[str, float]]:
    raw_landmarks = record.get("landmarks", [])
    if len(raw_landmarks) != len(LANDMARK_NAMES):
        return {}

    mapped: dict[str, dict[str, float]] = {}
    for name, landmark in zip(LANDMARK_NAMES, raw_landmarks):
        mapped[raw_name_to_engine_name(name)] = {
            "x": float(landmark["x"]),
            "y": float(landmark["y"]),
            "z": float(landmark.get("z", 0)),
            "visibility": float(landmark.get("visibility", 0)),
            "presence": float(landmark.get("presence", landmark.get("visibility", 0))),
        }
    return mapped


def side_landmark(mapped: dict[str, dict[str, float]], side: str, joint: str) -> dict[str, float] | None:
    return mapped.get(f"{side}.{joint}")


def confidence(landmark: dict[str, float]) -> float:
    return min(float(landmark.get("visibility", 0)), float(landmark.get("presence", 0)))


def build_motion_frames(args: argparse.Namespace, records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    support_side = args.support_side or ("left" if args.front_side == "right" else "right")
    frames: list[dict[str, Any]] = []
    skipped = 0

    for record in records:
        mapped = named_landmarks(record)
        if not mapped:
            skipped += 1
            continue

        landmarks = dict(mapped)
        for joint in SIDE_JOINTS:
            front = side_landmark(mapped, args.front_side, joint)
            support = side_landmark(mapped, support_side, joint)
            if front is not None:
                landmarks[f"primary.{joint}"] = dict(front)
            if support is not None:
                landmarks[f"secondary.{joint}"] = dict(support)

        frames.append(
            {
                "type": "motion_demo_pose",
                "exercise_id": args.exercise_id,
                "timestamp_ms": int(record["timestamp_ms"]),
                "image_size": record["image_size"],
                "phase": "unlabeled",
                "front_side": args.front_side,
                "support_side": support_side,
                "landmarks": landmarks,
            }
        )

    if skipped:
        print(f"motion-reference skipped_no_pose_or_incomplete={skipped}")
    return frames


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
        }

    for frame in frames:
        for anchor, fixed in solved.items():
            if anchor not in frame["landmarks"]:
                continue
            frame["landmarks"][anchor]["x"] = fixed["x"]
            frame["landmarks"][anchor]["y"] = fixed["y"]
    return solved


def angle_degrees(a: dict[str, float], b: dict[str, float], c: dict[str, float]) -> float:
    bax = a["x"] - b["x"]
    bay = a["y"] - b["y"]
    bcx = c["x"] - b["x"]
    bcy = c["y"] - b["y"]
    dot = (bax * bcx) + (bay * bcy)
    norm_a = max((bax * bax + bay * bay) ** 0.5, 1e-9)
    norm_c = max((bcx * bcx + bcy * bcy) ** 0.5, 1e-9)
    cos_angle = max(-1.0, min(1.0, dot / (norm_a * norm_c)))
    import math

    return math.degrees(math.acos(cos_angle))


def primary_knee_angle(frame: dict[str, Any]) -> float:
    landmarks = frame["landmarks"]
    return angle_degrees(
        landmarks["primary.hip"],
        landmarks["primary.knee"],
        landmarks["primary.ankle"],
    )


def frame_interval_ms(frames: list[dict[str, Any]]) -> int:
    intervals = [
        next_frame["timestamp_ms"] - frame["timestamp_ms"]
        for frame, next_frame in zip(frames, frames[1:])
        if next_frame["timestamp_ms"] > frame["timestamp_ms"]
    ]
    if not intervals:
        return 100
    return max(1, round(statistics.median(intervals)))


def relabel_timestamps(frames: list[dict[str, Any]], interval_ms: int) -> list[dict[str, Any]]:
    relabeled = [copy.deepcopy(frame) for frame in frames]
    for index, frame in enumerate(relabeled):
        frame["timestamp_ms"] = index * interval_ms
    return relabeled


def mix(a: float, b: float, factor: float) -> float:
    return a + ((b - a) * factor)


def landmark(x: float, y: float, z: float, visibility: float = 1.0, presence: float = 1.0) -> dict[str, float]:
    return {
        "x": float(x),
        "y": float(y),
        "z": float(z),
        "visibility": float(visibility),
        "presence": float(presence),
    }


def point_lerp(top: tuple[float, float, float], bottom: tuple[float, float, float], factor: float) -> dict[str, float]:
    return landmark(
        mix(top[0], bottom[0], factor),
        mix(top[1], bottom[1], factor),
        mix(top[2], bottom[2], factor),
    )


def add_foot_landmarks(
    landmarks: dict[str, dict[str, float]],
    prefix: str,
    ankle: dict[str, float],
    x_offset: float = 0,
) -> None:
    landmarks[f"{prefix}.heel"] = landmark(ankle["x"] - 0.045 + x_offset, ankle["y"] + 0.012, ankle["z"])
    landmarks[f"{prefix}.foot.index"] = landmark(ankle["x"] + 0.105 + x_offset, ankle["y"] + 0.018, ankle["z"] + 0.01)


def add_primary_side(
    landmarks: dict[str, dict[str, float]],
    prefix: str,
    points: dict[str, dict[str, float]],
    x_offset: float,
    z_offset: float,
) -> None:
    for joint, point in points.items():
        if joint == "nose":
            continue
        landmarks[f"{prefix}.{joint}"] = landmark(point["x"] + x_offset, point["y"], point["z"] + z_offset)
    add_foot_landmarks(landmarks, prefix, landmarks[f"{prefix}.ankle"])


def canonical_lunge_landmarks(factor: float) -> dict[str, dict[str, float]]:
    factor = max(0.0, min(1.0, factor))
    primary = {
        "nose": point_lerp((0.51, 0.13, -0.02), (0.52, 0.26, -0.02), factor),
        "shoulder": point_lerp((0.51, 0.25, 0.0), (0.52, 0.40, 0.0), factor),
        "elbow": point_lerp((0.55, 0.37, 0.03), (0.56, 0.50, 0.03), factor),
        "wrist": point_lerp((0.58, 0.50, 0.08), (0.58, 0.58, 0.08), factor),
        "hip": point_lerp((0.53, 0.45, 0.0), (0.53, 0.64, 0.0), factor),
        "knee": point_lerp((0.63, 0.66, 0.02), (0.76, 0.66, 0.02), factor),
        "ankle": landmark(0.77, 0.84, 0.05),
    }
    rear_ankle = point_lerp((0.35, 0.84, -0.18), (0.36, 0.815, -0.18), factor)
    rear_heel = point_lerp((0.315, 0.850, -0.18), (0.315, 0.792, -0.18), factor)
    rear_toe = landmark(0.42, 0.858, -0.19)

    landmarks: dict[str, dict[str, float]] = {
        "nose": dict(primary["nose"]),
    }
    for joint, point in primary.items():
        landmarks[f"primary.{joint}"] = dict(point)
    add_foot_landmarks(landmarks, "primary", primary["ankle"])
    add_primary_side(landmarks, "right", primary, x_offset=0, z_offset=0.10)
    add_primary_side(landmarks, "left", primary, x_offset=-0.24, z_offset=-0.10)

    secondary = {
        "shoulder": landmark(primary["shoulder"]["x"] - 0.03, primary["shoulder"]["y"], -0.18),
        "elbow": point_lerp((0.47, 0.37, -0.18), (0.48, 0.50, -0.18), factor),
        "wrist": point_lerp((0.45, 0.50, -0.18), (0.46, 0.58, -0.18), factor),
        "hip": landmark(primary["hip"]["x"] - 0.04, primary["hip"]["y"] + 0.005, -0.18),
        "knee": point_lerp((0.39, 0.66, -0.12), (0.43, 0.79, -0.16), factor),
        "ankle": rear_ankle,
        "heel": rear_heel,
        "foot.index": rear_toe,
    }
    for joint, point in secondary.items():
        landmarks[f"secondary.{joint}"] = dict(point)
    return landmarks


def canonical_lunge_retarget(frames: list[dict[str, Any]]) -> list[dict[str, Any]]:
    angles = [primary_knee_angle(frame) for frame in frames]
    top = max(angles)
    bottom = min(angles)
    span = max(top - bottom, 1e-6)
    retargeted: list[dict[str, Any]] = []
    for frame, angle in zip(frames, angles):
        factor = max(0.0, min(1.0, (top - angle) / span))
        next_frame = copy.deepcopy(frame)
        next_frame["phase"] = "canonical_lunge_retarget"
        next_frame["landmarks"] = canonical_lunge_landmarks(factor)
        retargeted.append(next_frame)
    return retargeted


def apply_retarget_mode(args: argparse.Namespace, frames: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if args.retarget == "raw":
        return frames
    if args.retarget == "canonical-lunge":
        return canonical_lunge_retarget(frames)
    raise SystemExit(f"unsupported retarget mode: {args.retarget}")


def descent_mirror_cycle(args: argparse.Namespace, frames: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if args.cycle_bottom_index is None:
        bottom_index = min(range(len(frames)), key=lambda index: primary_knee_angle(frames[index]))
    else:
        bottom_index = args.cycle_bottom_index
    if bottom_index <= 0 or bottom_index >= len(frames):
        raise SystemExit("--cycle-bottom-index must identify a non-initial frame")

    if args.cycle_start_index is None:
        start_index = max(range(0, bottom_index + 1), key=lambda index: primary_knee_angle(frames[index]))
    else:
        start_index = args.cycle_start_index
    if start_index < 0 or start_index >= bottom_index:
        raise SystemExit("--cycle-start-index must be before the bottom frame")

    descent = frames[start_index : bottom_index + 1]
    cycle = descent + list(reversed(descent[:-1]))
    return relabel_timestamps(cycle, frame_interval_ms(descent))


def apply_cycle_mode(args: argparse.Namespace, frames: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if args.cycle_mode == "raw":
        return frames
    if args.cycle_mode == "descent-mirror":
        return descent_mirror_cycle(args, frames)
    raise SystemExit(f"unsupported cycle mode: {args.cycle_mode}")


def lunge_summary(frames: list[dict[str, Any]]) -> dict[str, Any]:
    knee_angles: list[float] = []
    for frame in frames:
        landmarks = frame["landmarks"]
        try:
            knee_angles.append(
                angle_degrees(
                    landmarks["primary.hip"],
                    landmarks["primary.knee"],
                    landmarks["primary.ankle"],
                )
            )
        except KeyError:
            continue
    return {
        "frames": len(frames),
        "min_primary_knee_angle": round(min(knee_angles), 2) if knee_angles else None,
        "max_primary_knee_angle": round(max(knee_angles), 2) if knee_angles else None,
    }


def write_outputs(args: argparse.Namespace, frames: list[dict[str, Any]], solved_contacts: dict[str, dict[str, float]]) -> None:
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as handle:
        for frame in frames:
            handle.write(json.dumps(frame, separators=(",", ":")) + "\n")

    manifest = {
        "exercise_id": args.exercise_id,
        "raw_trace": str(args.raw),
        "output_trace": str(args.output),
        "front_side": args.front_side,
        "support_side": args.support_side or ("left" if args.front_side == "right" else "right"),
        "anchor_landmarks": sorted(solved_contacts),
        "cycle_mode": args.cycle_mode,
        "cycle_start_index": args.cycle_start_index,
        "cycle_bottom_index": args.cycle_bottom_index,
        "retarget": args.retarget,
        "summary": lunge_summary(frames),
        "viewer_command": (
            "cp "
            + str(args.output)
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
    parser.add_argument("--raw", type=Path, required=True, help="raw MediaPipe JSONL from export_mediapipe_reference_trace.py")
    parser.add_argument("--output", type=Path, required=True, help="motion_demo_pose JSONL output")
    parser.add_argument("--exercise-id", default="bodyweight_lunge")
    parser.add_argument("--front-side", choices=["left", "right"], default="right")
    parser.add_argument("--support-side", choices=["left", "right"])
    parser.add_argument("--smooth-alpha", type=float, default=0.45)
    parser.add_argument("--min-confidence", type=float, default=0.45)
    parser.add_argument(
        "--contact-policy",
        choices=["none", "lunge", "feet"],
        default="lunge",
        help=(
            "contact anchoring policy: none preserves raw MediaPipe motion; "
            "lunge pins the front foot and rear toe only; feet pins both heels and toes"
        ),
    )
    parser.add_argument(
        "--anchors",
        default=None,
        help="comma-separated landmarks whose x/y contact should be pinned",
    )
    parser.add_argument(
        "--cycle-mode",
        choices=["raw", "descent-mirror"],
        default="raw",
        help="raw keeps source timing; descent-mirror loops a selected descent back to the top",
    )
    parser.add_argument("--cycle-start-index", type=int, help="first frame for descent-mirror mode")
    parser.add_argument("--cycle-bottom-index", type=int, help="bottom frame for descent-mirror mode")
    parser.add_argument(
        "--retarget",
        choices=["raw", "canonical-lunge"],
        default="raw",
        help="raw preserves MediaPipe image coordinates; canonical-lunge drives a stationary display rig from the reference phase",
    )
    return parser.parse_args()


def contact_anchors(args: argparse.Namespace) -> set[str]:
    if args.anchors is not None:
        return {name.strip() for name in args.anchors.split(",") if name.strip()}
    if args.contact_policy == "none":
        return set()
    if args.contact_policy == "feet":
        return {
            "primary.ankle",
            "primary.heel",
            "primary.foot.index",
            "secondary.ankle",
            "secondary.heel",
            "secondary.foot.index",
        }
    return set(DEFAULT_ANCHORS)


def main() -> int:
    args = parse_args()
    args.raw = args.raw.expanduser().resolve()
    args.output = args.output.expanduser().resolve()

    if args.support_side == args.front_side:
        raise SystemExit("--support-side must differ from --front-side")

    records = load_raw_records(args.raw)
    frames = build_motion_frames(args, records)
    if not frames:
        raise SystemExit("no usable pose frames")

    frames = apply_cycle_mode(args, frames)
    frames = apply_retarget_mode(args, frames)
    anchors = contact_anchors(args)
    smooth_frames(frames, args.smooth_alpha, exclude=anchors)
    solved_contacts = anchor_contacts(frames, sorted(anchors), args.min_confidence)
    write_outputs(args, frames, solved_contacts)
    summary = lunge_summary(frames)
    print(
        "motion-reference normalized="
        f"{args.output} frames={summary['frames']} "
        f"primary_knee={summary['min_primary_knee_angle']}..{summary['max_primary_knee_angle']} "
        f"anchors={','.join(sorted(solved_contacts))}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
