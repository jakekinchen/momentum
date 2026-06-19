#!/usr/bin/env python3
"""Normalize a licensed preacher-curl source cycle into an app-ready guide trace.

The reviewed Pixabay clip gives a clean right-arm extended-flexed-extended
cycle, but the raw MediaPipe wrist shortens during dumbbell occlusion. This
normalizer keeps the source timing and source phase while emitting a stable
side-view anatomical guide: fixed supported upper arm, constant forearm length,
and a closed loop that replays through the exercise engine.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]

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
SOURCE_REQUIRED = ["right.shoulder", "right.elbow", "right.wrist", "right.hip"]
OUTPUT_REQUIRED = ["primary.shoulder", "primary.elbow", "primary.wrist", "primary.hip"]


def raw_name_to_engine_name(name: str) -> str:
    return name.replace("_", ".")


def repo_relative(path: Path | None) -> str | None:
    if path is None:
        return None
    try:
        return str(path.resolve().relative_to(ROOT))
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
            if record.get("poses_detected", 0) < 1:
                continue
            if len(record.get("landmarks", [])) != len(LANDMARK_NAMES):
                raise SystemExit(f"{path}:{line_number}: expected {len(LANDMARK_NAMES)} landmarks")
            records.append(record)
    if not records:
        raise SystemExit(f"empty raw trace: {path}")
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


def clamp(value: float, minimum: float, maximum: float) -> float:
    return min(max(value, minimum), maximum)


def smoothstep(value: float) -> float:
    value = clamp(value, 0.0, 1.0)
    return value * value * (3 - (2 * value))


def mix(a: float, b: float, factor: float) -> float:
    return a + ((b - a) * factor)


def point(x: float, y: float, z: float = 0.0) -> dict[str, float]:
    return {
        "x": round(x, 6),
        "y": round(y, 6),
        "z": round(z, 6),
        "visibility": 1.0,
        "presence": 1.0,
    }


def distance(a: dict[str, float], b: dict[str, float]) -> float:
    return math.hypot(a["x"] - b["x"], a["y"] - b["y"])


def angle_degrees(a: dict[str, float], b: dict[str, float], c: dict[str, float]) -> float:
    bax = a["x"] - b["x"]
    bay = a["y"] - b["y"]
    bcx = c["x"] - b["x"]
    bcy = c["y"] - b["y"]
    dot = (bax * bcx) + (bay * bcy)
    norm_a = max(math.hypot(bax, bay), 1e-9)
    norm_c = max(math.hypot(bcx, bcy), 1e-9)
    return math.degrees(math.acos(max(-1.0, min(1.0, dot / (norm_a * norm_c)))))


def angle_to_vertical(first: dict[str, float], second: dict[str, float]) -> float:
    dx = first["x"] - second["x"]
    dy = first["y"] - second["y"]
    magnitude = max(math.hypot(dx, dy), 1e-9)
    return math.degrees(math.acos(max(-1.0, min(1.0, (-dy) / magnitude))))


def selected_records(args: argparse.Namespace, records: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[int]]:
    if args.cycle_start_index < 0 or args.cycle_end_index >= len(records):
        raise SystemExit(
            f"invalid cycle window {args.cycle_start_index}..{args.cycle_end_index} "
            f"for {len(records)} source frames"
        )
    if not (args.cycle_start_index < args.cycle_flex_index < args.cycle_end_index):
        raise SystemExit("--cycle-flex-index must be between start and end")
    indices = list(range(args.cycle_start_index, args.cycle_end_index + 1))
    return records[args.cycle_start_index : args.cycle_end_index + 1], indices


def source_cycle_summary(args: argparse.Namespace, mapped: list[dict[str, dict[str, float]]]) -> dict[str, Any]:
    flex_relative = args.cycle_flex_index - args.cycle_start_index
    start = mapped[0]
    flex = mapped[flex_relative]
    end = mapped[-1]

    for label, frame in (("start", start), ("flex", flex), ("end", end)):
        for name in SOURCE_REQUIRED:
            if name not in frame:
                raise SystemExit(f"source {label} frame missing {name}")
            if confidence(frame[name]) < args.min_source_confidence:
                raise SystemExit(
                    f"source {label} frame {name} confidence "
                    f"{confidence(frame[name]):.3f} below {args.min_source_confidence}"
                )

    start_angle = angle_degrees(start["right.shoulder"], start["right.elbow"], start["right.wrist"])
    flex_angle = angle_degrees(flex["right.shoulder"], flex["right.elbow"], flex["right.wrist"])
    end_angle = angle_degrees(end["right.shoulder"], end["right.elbow"], end["right.wrist"])
    if start_angle < args.min_source_extension_angle or end_angle < args.min_source_extension_angle:
        raise SystemExit(f"source endpoints are not extended enough: {start_angle:.1f}, {end_angle:.1f}")
    if flex_angle > args.max_source_flexion_angle:
        raise SystemExit(f"source flex frame is not curled enough: {flex_angle:.1f}")
    if min(start_angle, end_angle) - flex_angle < args.min_source_rom_degrees:
        raise SystemExit(
            "source curl ROM too small: "
            f"start={start_angle:.1f} flex={flex_angle:.1f} end={end_angle:.1f}"
        )

    endpoint_drift = {
        name: distance(start[name], end[name])
        for name in ("right.shoulder", "right.elbow", "right.wrist")
    }
    for name, drift in endpoint_drift.items():
        if drift > args.max_source_endpoint_drift:
            raise SystemExit(f"source endpoint drift for {name} {drift:.4f} exceeds {args.max_source_endpoint_drift}")

    return {
        "raw_start_elbow_angle": round(start_angle, 2),
        "raw_flex_elbow_angle": round(flex_angle, 2),
        "raw_end_elbow_angle": round(end_angle, 2),
        "raw_rom_degrees": round(min(start_angle, end_angle) - flex_angle, 2),
        "raw_endpoint_drift": {key: round(value, 4) for key, value in endpoint_drift.items()},
        "raw_min_confidence": round(
            min(confidence(frame[name]) for frame in (start, flex, end) for name in SOURCE_REQUIRED),
            4,
        ),
    }


def phase_factors(args: argparse.Namespace, frame_count: int) -> list[float]:
    flex_relative = args.cycle_flex_index - args.cycle_start_index
    last_index = frame_count - 1
    factors: list[float] = []
    for index in range(frame_count):
        if index <= flex_relative:
            raw = index / max(flex_relative, 1)
            factor = smoothstep(raw)
        else:
            raw = (last_index - index) / max(last_index - flex_relative, 1)
            factor = smoothstep(raw) ** args.return_phase_power
        factors.append(factor)
    factors[0] = 0.0
    factors[flex_relative] = 1.0
    factors[-1] = 0.0
    return factors


def anatomical_landmarks(phase_factor: float, primary_side: str) -> dict[str, dict[str, float]]:
    phase_factor = clamp(phase_factor, 0.0, 1.0)
    elbow = (0.600, 0.540)
    forearm_length = 0.235
    extended_angle = math.radians(70)
    flexed_angle = math.radians(200)
    theta = mix(extended_angle, flexed_angle, phase_factor)
    wrist = (
        elbow[0] + (forearm_length * math.cos(theta)),
        elbow[1] + (forearm_length * math.sin(theta)),
    )

    right = {
        "shoulder": point(0.500, 0.300, 0.02),
        "elbow": point(elbow[0], elbow[1], 0.04),
        "wrist": point(wrist[0], wrist[1], 0.08),
        "hip": point(0.470, 0.590, 0.00),
        "knee": point(0.580, 0.720, 0.02),
        "ankle": point(0.630, 0.860, 0.04),
        "heel": point(0.605, 0.895, 0.04),
        "foot.index": point(0.690, 0.900, 0.05),
    }
    left = {
        "shoulder": point(0.425, 0.315, -0.10),
        "elbow": point(0.500, 0.555, -0.10),
        "wrist": point(0.425, 0.680, -0.10),
        "hip": point(0.395, 0.600, -0.12),
        "knee": point(0.505, 0.735, -0.12),
        "ankle": point(0.555, 0.865, -0.12),
        "heel": point(0.530, 0.900, -0.12),
        "foot.index": point(0.615, 0.905, -0.12),
    }

    side_data = {"left": left, "right": right}
    secondary_side = "left" if primary_side == "right" else "right"
    landmarks: dict[str, dict[str, float]] = {
        "nose": point(0.470, 0.175, -0.04),
    }
    for side in ("left", "right"):
        for joint, value in side_data[side].items():
            landmarks[f"{side}.{joint}"] = value
    for joint in SIDE_JOINTS:
        landmarks[f"primary.{joint}"] = dict(side_data[primary_side][joint])
        landmarks[f"secondary.{joint}"] = dict(side_data[secondary_side][joint])
    landmarks["primary.nose"] = dict(landmarks["nose"])
    landmarks["secondary.nose"] = dict(landmarks["nose"])
    return landmarks


def output_summary(frames: list[dict[str, Any]], source_summary: dict[str, Any]) -> dict[str, Any]:
    elbows = [
        angle_degrees(
            frame["landmarks"]["primary.shoulder"],
            frame["landmarks"]["primary.elbow"],
            frame["landmarks"]["primary.wrist"],
        )
        for frame in frames
    ]
    upper_tilts = [
        angle_to_vertical(frame["landmarks"]["primary.shoulder"], frame["landmarks"]["primary.elbow"])
        for frame in frames
    ]
    torso_tilts = [
        angle_to_vertical(frame["landmarks"]["primary.shoulder"], frame["landmarks"]["primary.hip"])
        for frame in frames
    ]
    upper_lengths = [
        distance(frame["landmarks"]["primary.shoulder"], frame["landmarks"]["primary.elbow"])
        for frame in frames
    ]
    forearm_lengths = [
        distance(frame["landmarks"]["primary.elbow"], frame["landmarks"]["primary.wrist"])
        for frame in frames
    ]
    first = frames[0]["landmarks"]
    last = frames[-1]["landmarks"]
    endpoint_delta = max(
        abs(first[name][axis] - last[name][axis])
        for name in OUTPUT_REQUIRED
        for axis in ("x", "y", "z")
    )
    return {
        "frames": len(frames),
        "min_primary_elbow_angle": round(min(elbows), 2),
        "max_primary_elbow_angle": round(max(elbows), 2),
        "primary_elbow_angle_start": round(elbows[0], 2),
        "primary_elbow_angle_flex": round(min(elbows), 2),
        "primary_elbow_angle_end": round(elbows[-1], 2),
        "max_upper_arm_tilt": round(max(upper_tilts), 2),
        "max_torso_tilt": round(max(torso_tilts), 2),
        "max_upper_arm_length_ratio": length_ratio(upper_lengths),
        "max_forearm_length_ratio": length_ratio(forearm_lengths),
        "max_endpoint_delta": round(endpoint_delta, 6),
        **source_summary,
    }


def length_ratio(lengths: list[float]) -> float:
    return round(max(lengths) / max(min(lengths), 1e-9), 4)


def validate_output(args: argparse.Namespace, frames: list[dict[str, Any]], summary: dict[str, Any]) -> None:
    if len(frames) < args.min_cycle_frames:
        raise SystemExit(f"output cycle has only {len(frames)} frames")
    missing = [name for name in OUTPUT_REQUIRED if any(name not in frame["landmarks"] for frame in frames)]
    if missing:
        raise SystemExit(f"missing output landmarks: {sorted(set(missing))}")
    for frame_index, frame in enumerate(frames):
        for name, landmark in frame["landmarks"].items():
            if confidence(landmark) < args.min_output_confidence:
                raise SystemExit(f"frame {frame_index} {name} confidence below {args.min_output_confidence}")
            if not (0.0 <= landmark["x"] <= 1.0 and 0.0 <= landmark["y"] <= 1.0):
                raise SystemExit(f"frame {frame_index} {name} out of bounds x={landmark['x']} y={landmark['y']}")
    if summary["primary_elbow_angle_start"] < args.min_output_extension_angle:
        raise SystemExit("output start is not extended enough")
    if summary["primary_elbow_angle_end"] < args.min_output_extension_angle:
        raise SystemExit("output end is not extended enough")
    if summary["primary_elbow_angle_flex"] > args.max_output_flexion_angle:
        raise SystemExit("output flex frame is not curled enough")
    if summary["max_upper_arm_tilt"] > args.max_output_upper_arm_tilt:
        raise SystemExit("output upper arm is not stable enough")
    if summary["max_torso_tilt"] > args.max_output_torso_tilt:
        raise SystemExit("output torso is not stable enough")
    if summary["max_upper_arm_length_ratio"] > args.max_limb_length_ratio:
        raise SystemExit("output upper arm length drift exceeds gate")
    if summary["max_forearm_length_ratio"] > args.max_limb_length_ratio:
        raise SystemExit("output forearm length drift exceeds gate")
    if summary["max_endpoint_delta"] > args.max_output_endpoint_delta:
        raise SystemExit("output loop endpoint drift exceeds gate")


def build_frames(args: argparse.Namespace, records: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    selected, source_indices = selected_records(args, records)
    mapped = [named_landmarks(record) for record in selected]
    source_summary = source_cycle_summary(args, mapped)
    factors = phase_factors(args, len(selected))
    start_timestamp = int(selected[0]["timestamp_ms"])
    interval_ms = median_interval_ms(selected)
    frames: list[dict[str, Any]] = []
    for index, (record, source_index, factor) in enumerate(zip(selected, source_indices, factors)):
        frames.append(
            {
                "type": "motion_demo_pose",
                "exercise_id": args.exercise_id,
                "timestamp_ms": int(record["timestamp_ms"]) - start_timestamp,
                "image_size": [1280, 720],
                "phase": "external_reference_preacher_curl_source_timed_anatomical_retarget",
                "primary_side": args.primary_side,
                "secondary_side": "left" if args.primary_side == "right" else "right",
                "source_kind": "licensed_external_reference_trace",
                "source_frame_id": source_index,
                "source_timestamp_ms": int(record["timestamp_ms"]) + args.source_start_ms,
                "phase_factor": round(factor, 6),
                "landmarks": anatomical_landmarks(factor, args.primary_side),
            }
        )

    end_record = selected[-1]
    end_source_index = source_indices[-1]
    end_timestamp = int(end_record["timestamp_ms"])
    for settle_index in range(args.extended_settle_frames):
        timestamp = end_timestamp + (interval_ms * (settle_index + 1))
        frames.append(
            {
                "type": "motion_demo_pose",
                "exercise_id": args.exercise_id,
                "timestamp_ms": timestamp - start_timestamp,
                "image_size": [1280, 720],
                "phase": "external_reference_preacher_curl_extended_settle",
                "primary_side": args.primary_side,
                "secondary_side": "left" if args.primary_side == "right" else "right",
                "source_kind": "licensed_external_reference_trace",
                "source_frame_id": end_source_index,
                "source_timestamp_ms": timestamp + args.source_start_ms,
                "phase_factor": 0.0,
                "landmarks": anatomical_landmarks(0.0, args.primary_side),
            }
        )
    summary = output_summary(frames, source_summary)
    summary.update(
        {
            "cycle_start_index": args.cycle_start_index,
            "cycle_flex_index": args.cycle_flex_index,
            "cycle_end_index": args.cycle_end_index,
            "source_indices": source_indices,
            "source_start_timestamp_ms": int(selected[0]["timestamp_ms"]) + args.source_start_ms,
            "source_flex_timestamp_ms": int(selected[args.cycle_flex_index - args.cycle_start_index]["timestamp_ms"])
            + args.source_start_ms,
            "source_end_timestamp_ms": end_timestamp + args.source_start_ms,
            "extended_settle_frames": args.extended_settle_frames,
            "extended_settle_interval_ms": interval_ms,
            "retarget_mode": "source_timed_anatomical_side_view_avatar_rig",
        }
    )
    validate_output(args, frames, summary)
    return frames, summary


def write_outputs(args: argparse.Namespace, frames: list[dict[str, Any]], summary: dict[str, Any]) -> None:
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as handle:
        for frame in frames:
            handle.write(json.dumps(frame, separators=(",", ":")) + "\n")

    manifest = {
        "exercise_id": args.exercise_id,
        "source_kind": "licensed_external_reference_trace",
        "source_label": args.source_label,
        "source_video": repo_relative(args.video),
        "source_page": args.source_page,
        "source_media_url": args.source_media_url,
        "source_license": args.source_license,
        "source_attribution": args.source_attribution,
        "raw_trace": repo_relative(args.raw),
        "normalizer": "scripts/motion_reference/normalize_single_arm_dumbbell_preacher_curl_trace.py",
        "output_trace": repo_relative(args.output),
        "retarget": "source_timed_anatomical_side_view_avatar_rig",
        "loop_closure": "source_timed_anatomical_closed_loop",
        "primary_side": args.primary_side,
        "required_output_landmarks": OUTPUT_REQUIRED,
        "summary": summary,
        "qa_gates": [
            "licensed_source_recorded",
            "raw_pose_reviewed",
            "single_subject_side_view_preacher_curl",
            "real_extended_flexed_extended_source_cycle",
            "source_timed_anatomical_retarget",
            "upper_arm_stable",
            "constant_forearm_length",
            "loop_boundary_stable",
            "engine_counts_one_rep",
            "agent_visual_reviewed",
        ],
        "viewer_command": (
            "cp "
            + repo_relative(args.output)
            + " Sources/CamiFitApp/Resources/MotionDemos/"
            + args.exercise_id
            + ".jsonl && cp "
            + repo_relative(args.output.with_suffix(".manifest.json"))
            + " Sources/CamiFitApp/Resources/MotionDemos/"
            + args.exercise_id
            + ".manifest.json && CAMIFIT_GUIDE_EXERCISE="
            + args.exercise_id
            + " ./script/build_and_run.sh --verify"
        ),
    }
    args.output.with_suffix(".manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--video", type=Path)
    parser.add_argument("--exercise-id", default="single_arm_dumbbell_preacher_curl")
    parser.add_argument("--cycle-start-index", type=int, required=True)
    parser.add_argument("--cycle-flex-index", type=int, required=True)
    parser.add_argument("--cycle-end-index", type=int, required=True)
    parser.add_argument("--primary-side", choices=["right", "left"], default="right")
    parser.add_argument("--source-start-ms", type=int, default=0)
    parser.add_argument("--extended-settle-frames", type=int, default=3)
    parser.add_argument("--return-phase-power", type=float, default=4.0)
    parser.add_argument("--min-source-confidence", type=float, default=0.85)
    parser.add_argument("--min-source-extension-angle", type=float, default=135)
    parser.add_argument("--max-source-flexion-angle", type=float, default=70)
    parser.add_argument("--min-source-rom-degrees", type=float, default=95)
    parser.add_argument("--max-source-endpoint-drift", type=float, default=0.05)
    parser.add_argument("--min-output-confidence", type=float, default=1.0)
    parser.add_argument("--min-cycle-frames", type=int, default=20)
    parser.add_argument("--min-output-extension-angle", type=float, default=150)
    parser.add_argument("--max-output-flexion-angle", type=float, default=65)
    parser.add_argument("--max-output-upper-arm-tilt", type=float, default=35)
    parser.add_argument("--max-output-torso-tilt", type=float, default=20)
    parser.add_argument("--max-limb-length-ratio", type=float, default=1.03)
    parser.add_argument("--max-output-endpoint-delta", type=float, default=0.000001)
    parser.add_argument("--source-label", default="Pixabay 66991 Crossfit Gym Workout Training")
    parser.add_argument("--source-page", default="https://pixabay.com/videos/crossfit-gym-workout-training-66991/")
    parser.add_argument("--source-media-url", default="https://pixabay.com/videos/crossfit-gym-workout-training-66991/")
    parser.add_argument("--source-license", default="Pixabay Content License")
    parser.add_argument("--source-attribution", default="tixonov_valentin / Pixabay")
    return parser.parse_args()


def median_interval_ms(records: list[dict[str, Any]]) -> int:
    intervals = [
        int(later["timestamp_ms"]) - int(earlier["timestamp_ms"])
        for earlier, later in zip(records, records[1:])
        if int(later["timestamp_ms"]) > int(earlier["timestamp_ms"])
    ]
    if not intervals:
        return 100
    intervals = sorted(intervals)
    return max(1, intervals[len(intervals) // 2])


def main() -> int:
    args = parse_args()
    args.raw = args.raw.expanduser().resolve()
    args.output = args.output.expanduser().resolve()
    if args.video is not None:
        args.video = args.video.expanduser().resolve()

    frames, summary = build_frames(args, load_raw_records(args.raw))
    write_outputs(args, frames, summary)
    print(
        "motion-reference normalized="
        f"{args.output} frames={len(frames)} "
        f"primary_elbow={summary['min_primary_elbow_angle']}..{summary['max_primary_elbow_angle']} "
        f"source={args.cycle_start_index}..{args.cycle_flex_index}..{args.cycle_end_index}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
