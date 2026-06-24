#!/usr/bin/env python3
"""Score raw detector output and normalized motion-reference traces."""

from __future__ import annotations

import argparse
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

KEY_RAW_INDICES = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28, 31, 32]
LEFT_RAW_INDICES = [11, 13, 15, 23, 25, 27, 31]
RIGHT_RAW_INDICES = [12, 14, 16, 24, 26, 28, 32]
KINEMATIC_POINTS = [
    "primary.shoulder",
    "primary.elbow",
    "primary.wrist",
    "primary.hip",
    "primary.knee",
    "primary.ankle",
    "primary.foot.index",
    "secondary.elbow",
    "secondary.foot.index",
]
SEGMENTS = [
    ("primary.shoulder", "primary.elbow"),
    ("primary.elbow", "primary.wrist"),
    ("primary.shoulder", "primary.hip"),
    ("primary.hip", "primary.knee"),
    ("primary.knee", "primary.ankle"),
    ("primary.ankle", "primary.foot.index"),
]
CONTACT_POINTS = [
    "primary.elbow",
    "secondary.elbow",
    "primary.foot.index",
    "secondary.foot.index",
]


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def rounded(value: float | None, digits: int = 6) -> float | None:
    if value is None:
        return None
    return round(value, digits)


def mean(values: list[float]) -> float | None:
    return statistics.mean(values) if values else None


def confidence(landmark: dict[str, Any]) -> float:
    visibility = float(landmark.get("visibility", 0))
    presence = float(landmark.get("presence", visibility))
    return min(visibility, presence)


def xy(landmark: dict[str, Any]) -> tuple[float, float]:
    return float(landmark["x"]), float(landmark["y"])


def distance(a: dict[str, Any], b: dict[str, Any]) -> float:
    ax, ay = xy(a)
    bx, by = xy(b)
    return math.hypot(ax - bx, ay - by)


def rms_delta(
    left: dict[str, dict[str, Any]],
    right: dict[str, dict[str, Any]],
    names: list[str],
) -> float:
    values: list[float] = []
    for name in names:
        if name in left and name in right:
            values.append(distance(left[name], right[name]))
    return math.sqrt(statistics.mean([value * value for value in values])) if values else 0.0


def raw_landmarks(row: dict[str, Any]) -> list[dict[str, Any]]:
    landmarks = row.get("landmarks")
    if row.get("type") == "pose" and isinstance(landmarks, list) and len(landmarks) == len(LANDMARK_NAMES):
        return [item for item in landmarks if isinstance(item, dict)]
    return []


def raw_side(landmarks: list[dict[str, Any]]) -> str:
    left = statistics.mean(confidence(landmarks[index]) for index in LEFT_RAW_INDICES)
    right = statistics.mean(confidence(landmarks[index]) for index in RIGHT_RAW_INDICES)
    return "left" if left >= right else "right"


def rejected_windows(frame_reasons: list[tuple[int, list[str]]]) -> list[dict[str, Any]]:
    windows: list[dict[str, Any]] = []
    start: int | None = None
    end: int | None = None
    reasons: set[str] = set()
    for frame_id, current in frame_reasons:
        if start is None:
            start = frame_id
            end = frame_id
            reasons = set(current)
            continue
        if end is not None and frame_id == end + 1:
            end = frame_id
            reasons.update(current)
            continue
        windows.append({"start_frame": start, "end_frame": end, "reasons": sorted(reasons)})
        start = frame_id
        end = frame_id
        reasons = set(current)
    if start is not None:
        windows.append({"start_frame": start, "end_frame": end, "reasons": sorted(reasons)})
    return windows


def detector_scorecard(raw_rows: list[dict[str, Any]], detectors: list[str]) -> dict[str, Any]:
    posed: list[tuple[int, list[dict[str, Any]]]] = []
    confidences: list[float] = []
    rejected: list[tuple[int, list[str]]] = []
    sides: list[str] = []

    for index, row in enumerate(raw_rows):
        landmarks = raw_landmarks(row)
        reasons: list[str] = []
        if not landmarks:
            reasons.append("no_pose")
        else:
            posed.append((index, landmarks))
            key_confidences = [confidence(landmarks[item]) for item in KEY_RAW_INDICES]
            frame_visibility = statistics.mean(key_confidences)
            confidences.extend(key_confidences)
            sides.append(raw_side(landmarks))
            if frame_visibility < 0.55:
                reasons.append("low_key_landmark_visibility")
            if any(
                not (0.0 <= float(landmarks[item]["x"]) <= 1.0 and 0.0 <= float(landmarks[item]["y"]) <= 1.0)
                for item in KEY_RAW_INDICES
            ):
                reasons.append("key_landmark_out_of_bounds")
        if reasons:
            rejected.append((index, reasons))

    jitter_values: list[float] = []
    for (_, previous), (_, current) in zip(posed, posed[1:]):
        deltas = [
            math.hypot(
                float(previous[item]["x"]) - float(current[item]["x"]),
                float(previous[item]["y"]) - float(current[item]["y"]),
            )
            for item in KEY_RAW_INDICES
        ]
        if deltas:
            jitter_values.append(math.sqrt(statistics.mean([value * value for value in deltas])))

    identity_flip_count = sum(
        1
        for previous, current in zip(sides, sides[1:])
        if previous != current
    )
    frame_coverage = len(posed) / len(raw_rows) if raw_rows else 0.0
    mean_visibility = mean(confidences) or 0.0
    temporal_jitter = mean(jitter_values) or 0.0

    failure_reasons: list[str] = []
    if len(detectors) < 2:
        failure_reasons.append("requires_at_least_two_detectors_for_agreement")
    if frame_coverage < 0.95:
        failure_reasons.append("frame_coverage_below_0.95")
    if mean_visibility < 0.60:
        failure_reasons.append("mean_visibility_below_0.60")
    if identity_flip_count:
        failure_reasons.append("identity_side_flips_detected")

    return {
        "status": "failed" if failure_reasons else "reviewed",
        "detectors": detectors,
        "metrics": {
            "frame_coverage": rounded(frame_coverage),
            "mean_visibility": rounded(mean_visibility),
            "detector_disagreement": 0.0 if len(detectors) == 1 else None,
            "identity_flip_count": identity_flip_count,
            "occlusion_count": sum(1 for _, reasons in rejected if "low_key_landmark_visibility" in reasons),
            "temporal_jitter": rounded(temporal_jitter),
            "rejected_frame_windows": rejected_windows(rejected),
        },
        "review": {
            "frame_count": len(raw_rows),
            "posed_frame_count": len(posed),
            "comparison_basis": "single_detector_temporal_quality" if len(detectors) == 1 else "multi_detector_agreement",
            "failure_reasons": failure_reasons,
        },
    }


def normalized_landmarks(row: dict[str, Any]) -> dict[str, dict[str, Any]]:
    landmarks = row.get("landmarks")
    if isinstance(landmarks, dict):
        return {
            name: value
            for name, value in landmarks.items()
            if isinstance(name, str) and isinstance(value, dict)
        }
    return {}


def angle_degrees(a: dict[str, Any], b: dict[str, Any], c: dict[str, Any]) -> float | None:
    bax = float(a["x"]) - float(b["x"])
    bay = float(a["y"]) - float(b["y"])
    bcx = float(c["x"]) - float(b["x"])
    bcy = float(c["y"]) - float(b["y"])
    left = math.hypot(bax, bay)
    right = math.hypot(bcx, bcy)
    if left == 0 or right == 0:
        return None
    cosine = max(-1.0, min(1.0, (bax * bcx + bay * bcy) / (left * right)))
    return math.degrees(math.acos(cosine))


def coefficient_of_variation(values: list[float]) -> float:
    if not values:
        return 0.0
    avg = statistics.mean(values)
    if avg == 0:
        return 0.0
    return statistics.pstdev(values) / avg


def point_range(frames: list[dict[str, dict[str, Any]]], names: list[str]) -> float:
    ranges: list[float] = []
    for name in names:
        xs = [float(frame[name]["x"]) for frame in frames if name in frame]
        ys = [float(frame[name]["y"]) for frame in frames if name in frame]
        if xs and ys:
            ranges.append(math.hypot(max(xs) - min(xs), max(ys) - min(ys)))
    return max(ranges) if ranges else 0.0


def smoothness_jerk(frames: list[dict[str, dict[str, Any]]]) -> float:
    values: list[float] = []
    for left, middle, right in zip(frames, frames[1:], frames[2:]):
        for name in KINEMATIC_POINTS:
            if name not in left or name not in middle or name not in right:
                continue
            ax, ay = xy(left[name])
            bx, by = xy(middle[name])
            cx, cy = xy(right[name])
            values.append(math.hypot(cx - 2 * bx + ax, cy - 2 * by + ay))
    return mean(values) or 0.0


def kinematic_scorecard(normalized_rows: list[dict[str, Any]]) -> dict[str, Any]:
    frames = [normalized_landmarks(row) for row in normalized_rows]
    frames = [frame for frame in frames if frame]

    segment_stabilities: dict[str, float] = {}
    for a_name, b_name in SEGMENTS:
        lengths = [
            distance(frame[a_name], frame[b_name])
            for frame in frames
            if a_name in frame and b_name in frame
        ]
        segment_stabilities[f"{a_name}:{b_name}"] = coefficient_of_variation(lengths)

    plank_angles = [
        angle
        for frame in frames
        if all(name in frame for name in ("primary.shoulder", "primary.hip", "primary.ankle"))
        for angle in [angle_degrees(frame["primary.shoulder"], frame["primary.hip"], frame["primary.ankle"])]
        if angle is not None
    ]
    elbow_angles = [
        angle
        for frame in frames
        if all(name in frame for name in ("primary.shoulder", "primary.elbow", "primary.wrist"))
        for angle in [angle_degrees(frame["primary.shoulder"], frame["primary.elbow"], frame["primary.wrist"])]
        if angle is not None
    ]
    primary_sides = [
        row.get("primary_side")
        for row in normalized_rows
        if isinstance(row.get("primary_side"), str)
    ]
    dominant_side_count = max((primary_sides.count(side) for side in set(primary_sides)), default=0)
    side_stability = dominant_side_count / len(primary_sides) if primary_sides else 0.0
    phase_values = [
        row.get("phase")
        for row in normalized_rows
        if isinstance(row.get("phase"), str)
    ]
    phase_monotonicity = 1.0 if len(set(phase_values)) <= 1 else 0.5
    loop_delta = rms_delta(frames[0], frames[-1], KINEMATIC_POINTS) if len(frames) >= 2 else 0.0
    contact_delta = point_range(frames, CONTACT_POINTS)
    max_limb_stability = max(segment_stabilities.values(), default=0.0)
    jerk = smoothness_jerk(frames)
    plank_mean = mean(plank_angles)
    elbow_mean = mean(elbow_angles)

    failure_reasons: list[str] = []
    if not frames:
        failure_reasons.append("missing_normalized_motion_frames")
    if max_limb_stability > 0.05:
        failure_reasons.append("limb_length_stability_above_0.05")
    if loop_delta > 0.03:
        failure_reasons.append("loop_boundary_delta_above_0.03")
    if contact_delta > 0.03:
        failure_reasons.append("contact_lock_delta_above_0.03")
    if jerk > 0.02:
        failure_reasons.append("smoothness_jerk_above_0.02")
    if plank_mean is None or plank_mean < 150:
        failure_reasons.append("plank_line_angle_below_150_degrees")
    if side_stability < 0.95:
        failure_reasons.append("primary_side_identity_unstable")
    if phase_monotonicity < 1.0:
        failure_reasons.append("phase_not_monotonic_for_static_hold")

    return {
        "status": "failed" if failure_reasons else "passed",
        "metrics": {
            "limb_length_stability": rounded(max_limb_stability),
            "joint_angle_limits": {
                "primary_plank_line_degrees": {
                    "mean": rounded(plank_mean),
                    "min": rounded(min(plank_angles)) if plank_angles else None,
                    "max": rounded(max(plank_angles)) if plank_angles else None,
                    "expected": ">=150",
                },
                "primary_elbow_degrees": {
                    "mean": rounded(elbow_mean),
                    "min": rounded(min(elbow_angles)) if elbow_angles else None,
                    "max": rounded(max(elbow_angles)) if elbow_angles else None,
                },
            },
            "smoothness_jerk": rounded(jerk),
            "loop_boundary_delta": rounded(loop_delta),
            "contact_lock_delta": rounded(contact_delta),
            "side_primary_identity_stability": rounded(side_stability),
            "phase_monotonicity": rounded(phase_monotonicity),
            "expected_rep_count": 0,
            "equipment_path_sanity": "none",
        },
        "review": {
            "frame_count": len(normalized_rows),
            "scored_frame_count": len(frames),
            "segment_stability": {key: rounded(value) for key, value in segment_stabilities.items()},
            "failure_reasons": failure_reasons,
        },
    }


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw", type=Path, required=True)
    parser.add_argument("--normalized", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--exercise-id", default="bodyweight_plank")
    parser.add_argument("--detector", action="append", default=["mediapipe"])
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    output_dir = args.output_dir or args.normalized.parent
    detector = detector_scorecard(read_jsonl(args.raw), args.detector)
    kinematic = kinematic_scorecard(read_jsonl(args.normalized))
    detector_path = output_dir / "detector_agreement_scorecard.json"
    kinematic_path = output_dir / "kinematic_scorecard.json"
    report_path = output_dir / "scorecard_report.json"
    write_json(detector_path, detector)
    write_json(kinematic_path, kinematic)
    write_json(
        report_path,
        {
            "exercise_id": args.exercise_id,
            "raw_trace": str(args.raw),
            "normalized_trace": str(args.normalized),
            "detector_agreement_scorecard_path": str(detector_path),
            "kinematic_scorecard_path": str(kinematic_path),
            "detector_agreement_scorecard": detector,
            "kinematic_scorecard": kinematic,
        },
    )
    print(
        f"motion-reference scorecards detector={detector['status']} "
        f"kinematic={kinematic['status']} output_dir={output_dir}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
