#!/usr/bin/env python3
"""Normalize a raw MediaPipe squat capture into app-ready demo landmarks."""

from __future__ import annotations

import argparse
import json
import math
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

PRIMARY_JOINTS = [
    "shoulder",
    "elbow",
    "wrist",
    "hip",
    "knee",
    "ankle",
    "heel",
    "foot.index",
]
CONTACT_JOINTS = {"ankle", "heel", "foot.index"}


def read_raw(path: Path) -> list[dict[str, Any]]:
    rows = []
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def normalize_landmark(raw: dict[str, Any]) -> dict[str, float]:
    visibility = float(raw.get("visibility", 1))
    return {
        "x": float(raw["x"]),
        "y": float(raw["y"]),
        "z": float(raw.get("z", 0)),
        "visibility": visibility,
        "presence": float(raw.get("presence", visibility)),
    }


def landmark_dict(row: dict[str, Any]) -> dict[str, dict[str, float]]:
    landmarks = row.get("landmarks") or []
    if len(landmarks) != len(LANDMARK_NAMES):
        return {}
    return {
        name: normalize_landmark(landmarks[index])
        for index, name in enumerate(LANDMARK_NAMES)
    }


def angle_degrees(
    a: dict[str, float] | None,
    b: dict[str, float] | None,
    c: dict[str, float] | None,
) -> float | None:
    if not a or not b or not c:
        return None
    bax = a["x"] - b["x"]
    bay = a["y"] - b["y"]
    bcx = c["x"] - b["x"]
    bcy = c["y"] - b["y"]
    norm_a = math.hypot(bax, bay)
    norm_c = math.hypot(bcx, bcy)
    if norm_a < 1e-9 or norm_c < 1e-9:
        return None
    cosine = max(-1.0, min(1.0, ((bax * bcx) + (bay * bcy)) / (norm_a * norm_c)))
    return math.degrees(math.acos(cosine))


def side_score(rows: list[dict[str, Any]], side: str) -> float:
    values = []
    for row in rows:
        landmarks = landmark_dict(row)
        for joint in ("shoulder", "hip", "knee", "ankle", "heel", "foot.index"):
            landmark = landmarks.get(f"{side}.{joint}")
            if landmark:
                values.append(landmark["visibility"])
    return statistics.mean(values) if values else -1


def strongest_side(rows: list[dict[str, Any]]) -> str:
    left = side_score(rows, "left")
    right = side_score(rows, "right")
    return "right" if right > left else "left"


def metrics_for_side(rows: list[dict[str, Any]], side: str) -> list[dict[str, float]]:
    spatial_outliers = spatial_outlier_indices(rows, side, [f"{side}.knee", f"{side}.ankle"])
    metrics = []
    for index, row in enumerate(rows):
        landmarks = landmark_dict(row)
        hip = landmarks.get(f"{side}.hip")
        knee = landmarks.get(f"{side}.knee")
        ankle = landmarks.get(f"{side}.ankle")
        angle = angle_degrees(hip, knee, ankle)
        confidence_values = [
            landmark["visibility"]
            for landmark in (hip, knee, ankle)
            if landmark is not None
        ]
        metrics.append(
            {
                "index": float(index),
                "knee_angle": angle if angle is not None else float("nan"),
                "hip_y": hip["y"] if hip else float("nan"),
                "confidence": statistics.mean(confidence_values) if confidence_values else 0.0,
                "spatial_outlier": 1.0 if index in spatial_outliers else 0.0,
            }
        )
    return metrics


def robust_axis_outliers(values: list[float], minimum_threshold: float) -> set[int]:
    finite = [value for value in values if not math.isnan(value)]
    if len(finite) < 5:
        return set()
    median = statistics.median(finite)
    deviations = [abs(value - median) for value in finite]
    mad = statistics.median(deviations)
    threshold = max(minimum_threshold, mad * 8.0)
    return {
        index
        for index, value in enumerate(values)
        if not math.isnan(value) and abs(value - median) > threshold
    }


def spatial_outlier_indices(rows: list[dict[str, Any]], side: str, names: list[str]) -> set[int]:
    outliers: set[int] = set()
    for name in names:
        xs = []
        ys = []
        for row in rows:
            landmark = landmark_dict(row).get(name)
            xs.append(landmark["x"] if landmark else float("nan"))
            ys.append(landmark["y"] if landmark else float("nan"))
        outliers.update(robust_axis_outliers(xs, minimum_threshold=0.075))
        outliers.update(robust_axis_outliers(ys, minimum_threshold=0.055))
    return outliers


def smooth_values(values: list[float], window: int) -> list[float]:
    if window <= 1 or len(values) < 3:
        return values
    radius = window // 2
    output = []
    for index in range(len(values)):
        neighbors = [
            values[i]
            for i in range(max(0, index - radius), min(len(values), index + radius + 1))
            if not math.isnan(values[i])
        ]
        output.append(statistics.mean(neighbors) if neighbors else values[index])
    return output


def detect_cycle(
    rows: list[dict[str, Any]],
    side: str,
    bottom_index: int | None,
    top_index: int | None,
) -> tuple[int, int]:
    bottom_was_requested = bottom_index is not None
    if bottom_index is not None and top_index is not None:
        if top_index <= bottom_index:
            raise SystemExit("--cycle-top-index must be greater than --cycle-bottom-index")
        return bottom_index, top_index

    metrics = metrics_for_side(rows, side)
    raw_angles = [
        item["knee_angle"] if item["spatial_outlier"] < 0.5 else float("nan")
        for item in metrics
    ]
    raw_hip_ys = [
        item["hip_y"] if item["spatial_outlier"] < 0.5 else float("nan")
        for item in metrics
    ]
    angles = smooth_values(raw_angles, 5)
    hip_ys = smooth_values(raw_hip_ys, 5)
    valid = [
        index
        for index, item in enumerate(metrics)
        if item["confidence"] >= 0.60
        and item["spatial_outlier"] < 0.5
        and not math.isnan(angles[index])
        and not math.isnan(hip_ys[index])
    ]
    if len(valid) < 8:
        raise SystemExit("not enough confident squat frames to detect a cycle")

    min_angle = min(angles[index] for index in valid)
    max_angle = max(angles[index] for index in valid)
    min_hip_y = min(hip_ys[index] for index in valid)
    max_hip_y = max(hip_ys[index] for index in valid)

    def normalized(value: float, low: float, high: float) -> float:
        span = max(high - low, 1e-9)
        return (value - low) / span

    if bottom_index is None:
        preliminary_bottom = max(
            valid,
            key=lambda index: (
                normalized(max_angle - angles[index], max_angle - max_angle, max_angle - min_angle)
                + normalized(hip_ys[index], min_hip_y, max_hip_y)
            ),
        )
        nearby = [
            index
            for index in valid
            if abs(index - preliminary_bottom) <= 6 and not math.isnan(raw_angles[index])
        ]
        bottom_index = min(nearby or [preliminary_bottom], key=lambda index: raw_angles[index])

    if top_index is None:
        angle_threshold = min_angle + ((max_angle - min_angle) * 0.86)
        hip_threshold = max_hip_y - ((max_hip_y - min_hip_y) * 0.72)
        candidates = [
            index
            for index in valid
            if index > bottom_index + 4
            and angles[index] >= angle_threshold
            and hip_ys[index] <= hip_threshold
        ]
        if candidates:
            preliminary_top = candidates[0]
            nearby = [
                index
                for index in valid
                if preliminary_top <= index <= preliminary_top + 6
                and not math.isnan(raw_angles[index])
            ]
            top_index = max(nearby or [preliminary_top], key=lambda index: raw_angles[index])
        else:
            after_bottom = [index for index in valid if index > bottom_index]
            if not after_bottom:
                raise SystemExit("could not detect a top frame after the squat bottom")
            top_index = max(after_bottom, key=lambda index: angles[index] - hip_ys[index])

    if not bottom_was_requested and top_index - bottom_index < 8:
        later_bottoms = [
            index
            for index in valid
            if index < top_index - 7 and not math.isnan(raw_angles[index])
        ]
        if later_bottoms:
            bottom_index = min(later_bottoms, key=lambda index: raw_angles[index])

    if top_index - bottom_index < 8:
        raise SystemExit(
            f"detected squat cycle is too short: bottom={bottom_index} top={top_index}"
        )
    return bottom_index, top_index


def joint_name(name: str) -> str:
    for prefix in ("primary.", "secondary."):
        if name.startswith(prefix):
            return name[len(prefix) :]
    return name


def smooth_frames(frames: list[dict[str, Any]], window: int) -> list[dict[str, Any]]:
    if window <= 1 or len(frames) < 3:
        return frames
    radius = window // 2
    names = sorted({name for frame in frames for name in frame["landmarks"]})
    smoothed: list[dict[str, Any]] = []

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


def mix(a: float, b: float, factor: float) -> float:
    return a + ((b - a) * factor)


def landmark(
    x: float,
    y: float,
    z: float = 0.0,
    visibility: float = 1.0,
    presence: float = 1.0,
) -> dict[str, float]:
    return {
        "x": float(x),
        "y": float(y),
        "z": float(z),
        "visibility": float(visibility),
        "presence": float(presence),
    }


def point_lerp(
    top: tuple[float, float, float],
    bottom: tuple[float, float, float],
    factor: float,
) -> dict[str, float]:
    return landmark(
        mix(top[0], bottom[0], factor),
        mix(top[1], bottom[1], factor),
        mix(top[2], bottom[2], factor),
    )


def smoothstep(factor: float) -> float:
    factor = max(0.0, min(1.0, factor))
    return factor * factor * (3 - (2 * factor))


def add_foot(
    landmarks: dict[str, dict[str, float]],
    prefix: str,
    heel: tuple[float, float, float],
    toe: tuple[float, float, float],
    ankle: tuple[float, float, float] | None = None,
) -> None:
    landmarks[f"{prefix}.heel"] = landmark(*heel)
    landmarks[f"{prefix}.foot.index"] = landmark(*toe)
    if ankle is not None:
        landmarks[f"{prefix}.ankle"] = landmark(*ankle)


def add_alias_side(
    landmarks: dict[str, dict[str, float]],
    side: str,
    source_prefix: str,
    z_offset: float,
) -> None:
    for joint in PRIMARY_JOINTS:
        source = landmarks.get(f"{source_prefix}.{joint}")
        if source:
            landmarks[f"{side}.{joint}"] = landmark(
                source["x"],
                source["y"],
                source["z"] + z_offset,
                source["visibility"],
                source["presence"],
            )


def canonical_squat_landmarks(factor: float) -> dict[str, dict[str, float]]:
    factor = smoothstep(factor)
    primary = {
        "nose": point_lerp((0.590, 0.175, -0.02), (0.610, 0.315, -0.02), factor),
        "shoulder": point_lerp((0.560, 0.295, 0.00), (0.565, 0.420, 0.00), factor),
        "elbow": point_lerp((0.620, 0.405, 0.03), (0.675, 0.385, 0.03), factor),
        "wrist": point_lerp((0.665, 0.540, 0.08), (0.735, 0.455, 0.08), factor),
        "hip": point_lerp((0.555, 0.485, 0.00), (0.500, 0.600, 0.00), factor),
        "knee": point_lerp((0.555, 0.665, 0.02), (0.650, 0.650, 0.02), factor),
        "ankle": landmark(0.525, 0.825, 0.05),
    }
    secondary = {
        "shoulder": landmark(primary["shoulder"]["x"] - 0.045, primary["shoulder"]["y"], -0.16),
        "elbow": point_lerp((0.575, 0.405, -0.15), (0.635, 0.390, -0.15), factor),
        "wrist": point_lerp((0.620, 0.540, -0.14), (0.690, 0.460, -0.14), factor),
        "hip": landmark(primary["hip"]["x"] - 0.045, primary["hip"]["y"], -0.16),
        "knee": point_lerp((0.510, 0.665, -0.14), (0.605, 0.650, -0.14), factor),
        "ankle": landmark(0.480, 0.825, -0.15),
    }

    landmarks = {"nose": dict(primary["nose"]), "primary.nose": dict(primary["nose"])}
    for joint, point in primary.items():
        landmarks[f"primary.{joint}"] = dict(point)
    for joint, point in secondary.items():
        landmarks[f"secondary.{joint}"] = dict(point)

    add_foot(landmarks, "primary", (0.455, 0.862, 0.05), (0.690, 0.862, 0.06))
    add_foot(landmarks, "secondary", (0.410, 0.862, -0.15), (0.645, 0.862, -0.14))
    add_alias_side(landmarks, "right", "primary", z_offset=0.10)
    add_alias_side(landmarks, "left", "secondary", z_offset=-0.02)
    return landmarks


def knee_angle(frame: dict[str, Any]) -> float:
    landmarks = frame["landmarks"]
    angle = angle_degrees(
        landmarks.get("primary.hip"),
        landmarks.get("primary.knee"),
        landmarks.get("primary.ankle"),
    )
    return angle if angle is not None else float("nan")


def phase_factors_from_loop(frames: list[dict[str, Any]], window: int) -> list[float]:
    angles = [knee_angle(frame) for frame in frames]
    smoothed = smooth_values(angles, max(1, window))
    finite = [value for value in smoothed if not math.isnan(value)]
    if len(finite) < 2:
        return [0.0 for _ in frames]
    top = max(finite)
    bottom = min(finite)
    span = max(top - bottom, 1e-6)
    return [
        max(0.0, min(1.0, (top - value) / span)) if not math.isnan(value) else 0.0
        for value in smoothed
    ]


def retarget_to_canonical_squat(frames: list[dict[str, Any]], phase_window: int) -> list[dict[str, Any]]:
    factors = phase_factors_from_loop(frames, phase_window)
    retargeted: list[dict[str, Any]] = []
    for frame, factor in zip(frames, factors):
        retargeted.append(
            {
                **frame,
                "landmarks": canonical_squat_landmarks(factor),
            }
        )
    if len(retargeted) > 1:
        retargeted[-1]["landmarks"] = clone_frame(retargeted[0])["landmarks"]
    return retargeted


def contact_medians(frames: list[dict[str, Any]]) -> dict[str, dict[str, float]]:
    medians: dict[str, dict[str, float]] = {}
    for name in [f"primary.{joint}" for joint in CONTACT_JOINTS]:
        values = {axis: [] for axis in ("x", "y", "z")}
        confidence = []
        for frame in frames:
            landmark = frame["landmarks"].get(name)
            if not landmark or landmark["visibility"] < 0.55:
                continue
            for axis in values:
                values[axis].append(landmark[axis])
            confidence.append(landmark["visibility"])
        if all(values[axis] for axis in values):
            medians[name] = {
                "x": statistics.median(values["x"]),
                "y": statistics.median(values["y"]),
                "z": statistics.median(values["z"]),
                "visibility": max(0.86, statistics.median(confidence)),
                "presence": max(0.86, statistics.median(confidence)),
            }
    return medians


def repair_spatial_outliers(frames: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if len(frames) < 5:
        return frames
    repaired = [clone_frame(frame) for frame in frames]
    names = [f"primary.{joint}" for joint in PRIMARY_JOINTS]

    for name in names:
        xs = [
            frame["landmarks"][name]["x"] if name in frame["landmarks"] else float("nan")
            for frame in repaired
        ]
        ys = [
            frame["landmarks"][name]["y"] if name in frame["landmarks"] else float("nan")
            for frame in repaired
        ]
        bad_indices = robust_axis_outliers(xs, minimum_threshold=0.075)
        bad_indices.update(robust_axis_outliers(ys, minimum_threshold=0.055))
        if not bad_indices:
            continue

        good_indices = [
            index
            for index, frame in enumerate(repaired)
            if index not in bad_indices and name in frame["landmarks"]
        ]
        for index in bad_indices:
            if name not in repaired[index]["landmarks"] or len(good_indices) < 2:
                continue
            previous = max((item for item in good_indices if item < index), default=None)
            next_index = min((item for item in good_indices if item > index), default=None)
            if previous is None:
                replacement = repaired[next_index]["landmarks"][name] if next_index is not None else None
            elif next_index is None:
                replacement = repaired[previous]["landmarks"][name]
            else:
                span = max(next_index - previous, 1)
                factor = (index - previous) / span
                before = repaired[previous]["landmarks"][name]
                after = repaired[next_index]["landmarks"][name]
                replacement = {
                    axis: before[axis] + ((after[axis] - before[axis]) * factor)
                    for axis in ("x", "y", "z", "visibility", "presence")
                }
            if replacement is not None:
                repaired[index]["landmarks"][name] = dict(replacement)
    return repaired


def add_synthetic_secondary(
    landmarks: dict[str, dict[str, float]],
    *,
    x_offset: float,
    z_offset: float,
) -> None:
    for joint in PRIMARY_JOINTS:
        source = landmarks.get(f"primary.{joint}")
        if not source:
            continue
        secondary = dict(source)
        secondary["x"] = source["x"] + x_offset
        secondary["z"] = source["z"] + z_offset
        secondary["visibility"] = min(source["visibility"], 0.90)
        secondary["presence"] = min(source["presence"], 0.90)
        landmarks[f"secondary.{joint}"] = secondary


def make_frame(row: dict[str, Any], frame_id: int, timestamp_ms: int, primary_side: str) -> dict[str, Any]:
    raw_landmarks = landmark_dict(row)
    landmarks: dict[str, dict[str, float]] = {}

    if "nose" in raw_landmarks:
        landmarks["nose"] = raw_landmarks["nose"]
        landmarks["primary.nose"] = raw_landmarks["nose"]

    for joint in PRIMARY_JOINTS:
        source = raw_landmarks.get(f"{primary_side}.{joint}")
        if source:
            landmarks[f"primary.{joint}"] = source

    return {
        "type": "motion_demo_pose",
        "frame_id": frame_id,
        "timestamp_ms": timestamp_ms,
        "image_size": row.get("image_size", [1080, 1920]),
        "landmarks": landmarks,
    }


def build_ascent_frames(
    rows: list[dict[str, Any]],
    *,
    primary_side: str,
    bottom_index: int,
    top_index: int,
    smooth_window: int,
    secondary_x_offset: float,
    secondary_z_offset: float,
) -> list[dict[str, Any]]:
    selected = rows[bottom_index : top_index + 1]
    start_ms = int(selected[0]["timestamp_ms"])
    frames = [
        make_frame(
            row,
            frame_id=index,
            timestamp_ms=int(row["timestamp_ms"]) - start_ms,
            primary_side=primary_side,
        )
        for index, row in enumerate(selected)
    ]
    frames = repair_spatial_outliers(frames)
    frames = smooth_frames(frames, smooth_window)

    medians = contact_medians(frames)
    for frame in frames:
        for name, pinned in medians.items():
            if name in frame["landmarks"]:
                frame["landmarks"][name] = dict(pinned)
        add_synthetic_secondary(
            frame["landmarks"],
            x_offset=secondary_x_offset,
            z_offset=secondary_z_offset,
        )
    return frames


def clone_frame(frame: dict[str, Any]) -> dict[str, Any]:
    return json.loads(json.dumps(frame))


def make_mirrored_top_bottom_top_loop(ascent: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if len(ascent) < 2:
        return ascent

    interval_values = [
        ascent[index]["timestamp_ms"] - ascent[index - 1]["timestamp_ms"]
        for index in range(1, len(ascent))
        if ascent[index]["timestamp_ms"] > ascent[index - 1]["timestamp_ms"]
    ]
    interval = int(statistics.median(interval_values)) if interval_values else 67
    sequence = [clone_frame(frame) for frame in reversed(ascent)]
    sequence.extend(clone_frame(frame) for frame in ascent[1:])
    sequence.append(clone_frame(sequence[0]))

    for index, frame in enumerate(sequence):
        frame["frame_id"] = index
        frame["timestamp_ms"] = index * interval
    return sequence


def write_manifest(
    args: argparse.Namespace,
    output: Path,
    *,
    primary_side: str,
    bottom_index: int,
    top_index: int,
    frame_count: int,
) -> None:
    capture_label = args.video.parent.name if args.video else args.raw.parent.name
    manifest = {
        "exercise_id": args.exercise_id,
        "source_kind": "trainer_reference_trace",
        "source_label": (
            f"first-party webcam squat capture {capture_label}; "
            f"primary_side={primary_side}"
        ),
        "source_video": str(args.video) if args.video else None,
        "raw_trace": str(args.raw),
        "normalizer": "scripts/motion_reference/normalize_squat_trace.py",
        "retarget": args.retarget,
        "cycle_mode": "captured_ascent_mirrored_to_top_bottom_top",
        "cycle_bottom_index": bottom_index,
        "cycle_top_index": top_index,
        "contact_policy": "pin_primary_and_synthetic_secondary_ankle_heel_toe",
        "secondary_policy": (
            "canonical_depth_offset"
            if args.retarget == "canonical-squat"
            else "synthetic_depth_offset_from_primary"
        ),
        "smooth_window": args.smooth_window,
        "phase_window": args.phase_window,
        "frame_count": frame_count,
    }
    output.with_suffix(".manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n",
        encoding="utf-8",
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--video", type=Path)
    parser.add_argument("--exercise-id", default="bodyweight_squat")
    parser.add_argument("--primary-side", choices=["auto", "left", "right"], default="auto")
    parser.add_argument("--cycle-bottom-index", type=int)
    parser.add_argument("--cycle-top-index", type=int)
    parser.add_argument("--smooth-window", type=int, default=5)
    parser.add_argument("--phase-window", type=int, default=5)
    parser.add_argument("--retarget", choices=["canonical-squat", "raw"], default="canonical-squat")
    parser.add_argument("--secondary-x-offset", type=float, default=-0.045)
    parser.add_argument("--secondary-z-offset", type=float, default=-0.14)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    rows = read_raw(args.raw)
    if not rows:
        raise SystemExit(f"empty raw trace: {args.raw}")

    primary_side = strongest_side(rows) if args.primary_side == "auto" else args.primary_side
    bottom_index, top_index = detect_cycle(
        rows,
        primary_side,
        args.cycle_bottom_index,
        args.cycle_top_index,
    )
    ascent = build_ascent_frames(
        rows,
        primary_side=primary_side,
        bottom_index=bottom_index,
        top_index=top_index,
        smooth_window=args.smooth_window,
        secondary_x_offset=args.secondary_x_offset,
        secondary_z_offset=args.secondary_z_offset,
    )
    frames = make_mirrored_top_bottom_top_loop(ascent)
    if args.retarget == "canonical-squat":
        frames = retarget_to_canonical_squat(frames, args.phase_window)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as handle:
        for frame in frames:
            handle.write(json.dumps(frame, separators=(",", ":")) + "\n")
    write_manifest(
        args,
        args.output,
        primary_side=primary_side,
        bottom_index=bottom_index,
        top_index=top_index,
        frame_count=len(frames),
    )
    print(
        "motion-reference "
        f"normalized={args.output} frames={len(frames)} "
        f"primary_side={primary_side} bottom={bottom_index} top={top_index}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
