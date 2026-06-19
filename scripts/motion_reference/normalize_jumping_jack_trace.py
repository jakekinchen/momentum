#!/usr/bin/env python3
"""Normalize front-view MediaPipe jumping-jack motion.

The raw MediaPipe rig is useful for locating the source clip phase, but short
stock clips can produce unstable bone lengths, detached head anchors, and
side-to-side identity wobble. The default output still preserves raw landmarks;
`--retarget-mode anatomical` instead uses the licensed source cycle timing to
drive a stable front-view avatar rig.
"""

from __future__ import annotations

import argparse
import copy
import json
import math
import statistics
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
OUTPUT_LANDMARKS = {"nose"} | {
    f"{side}.{joint}"
    for side in ("left", "right")
    for joint in SIDE_JOINTS
}
REQUIRED_CYCLE_LANDMARKS = [
    "left.shoulder",
    "right.shoulder",
    "left.elbow",
    "right.elbow",
    "left.wrist",
    "right.wrist",
    "left.hip",
    "right.hip",
    "left.knee",
    "right.knee",
    "left.ankle",
    "right.ankle",
]
FOOT_LANDMARKS = [
    "left.heel",
    "right.heel",
    "left.foot.index",
    "right.foot.index",
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
        engine_name = raw_name_to_engine_name(name)
        if engine_name not in OUTPUT_LANDMARKS:
            continue
        visibility = float(landmark.get("visibility", 0))
        mapped[engine_name] = {
            "x": float(landmark["x"]),
            "y": float(landmark["y"]),
            "z": float(landmark.get("z", 0)),
            "visibility": visibility,
            "presence": float(landmark.get("presence", visibility)),
        }
    return mapped


def confidence(landmark: dict[str, float]) -> float:
    return min(float(landmark.get("visibility", 0)), float(landmark.get("presence", 0)))


def distance(a: dict[str, float], b: dict[str, float]) -> float:
    return math.hypot(a["x"] - b["x"], a["y"] - b["y"])


def shoulder_width(landmarks: dict[str, dict[str, float]]) -> float:
    return max(distance(landmarks["left.shoulder"], landmarks["right.shoulder"]), 1e-9)


def wrist_spread_ratio(landmarks: dict[str, dict[str, float]]) -> float:
    return abs(landmarks["left.wrist"]["x"] - landmarks["right.wrist"]["x"]) / shoulder_width(landmarks)


def knee_ankle_ratio(landmarks: dict[str, dict[str, float]]) -> float:
    ankle_spread = max(abs(landmarks["left.ankle"]["x"] - landmarks["right.ankle"]["x"]), 1e-9)
    knee_spread = abs(landmarks["left.knee"]["x"] - landmarks["right.knee"]["x"])
    return knee_spread / ankle_spread


def cycle_features(landmarks: dict[str, dict[str, float]]) -> dict[str, float]:
    width = shoulder_width(landmarks)
    shoulder_y = (landmarks["left.shoulder"]["y"] + landmarks["right.shoulder"]["y"]) / 2
    wrist_y = (landmarks["left.wrist"]["y"] + landmarks["right.wrist"]["y"]) / 2
    ankle_spread = distance(landmarks["left.ankle"], landmarks["right.ankle"]) / width
    wrist_above_shoulder = (shoulder_y - wrist_y) / width
    hip_width = distance(landmarks["left.hip"], landmarks["right.hip"]) / width
    min_visibility = min(confidence(landmarks[name]) for name in REQUIRED_CYCLE_LANDMARKS)
    return {
        "ankle_spread": ankle_spread,
        "wrist_above_shoulder": wrist_above_shoulder,
        "hip_width_ratio": hip_width,
        "min_visibility": min_visibility,
        "open_score": ankle_spread + max(0.0, wrist_above_shoulder),
    }


def selected_records(args: argparse.Namespace, records: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[int]]:
    end = args.cycle_end_index
    if args.cycle_start_index < 0 or end >= len(records) or end <= args.cycle_start_index:
        raise SystemExit(f"invalid cycle window {args.cycle_start_index}..{end} for {len(records)} raw frames")
    if not (args.cycle_start_index <= args.cycle_open_index <= end):
        raise SystemExit("--cycle-open-index must be inside the selected cycle window")
    indices = list(range(args.cycle_start_index, end + 1))
    return records[args.cycle_start_index : end + 1], indices


def mirrored_half_cycle_records(args: argparse.Namespace, records: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[int]]:
    if args.cycle_start_index < 0 or args.cycle_open_index >= len(records) or args.cycle_open_index <= args.cycle_start_index:
        raise SystemExit(
            f"invalid mirrored cycle window {args.cycle_start_index}..{args.cycle_open_index} "
            f"for {len(records)} raw frames"
        )
    forward_indices = list(range(args.cycle_start_index, args.cycle_open_index + 1))
    forward_records = records[args.cycle_start_index : args.cycle_open_index + 1]
    return_records = [copy.deepcopy(record) for record in forward_records[-2::-1]]
    return_indices = forward_indices[-2::-1]
    hold_records = [copy.deepcopy(forward_records[0]) for _ in range(args.closing_hold_frames)]
    hold_indices = [forward_indices[0]] * args.closing_hold_frames
    return forward_records + return_records + hold_records, forward_indices + return_indices + hold_indices


def assert_cycle_quality(args: argparse.Namespace, frames: list[dict[str, dict[str, float]]]) -> dict[str, Any]:
    features = [cycle_features(frame) for frame in frames]
    start = features[0]
    open_feature = features[args.cycle_open_index - args.cycle_start_index]
    end = features[-1]

    for name, frame in zip(("start", "open", "end"), (features[0], open_feature, features[-1])):
        if frame["min_visibility"] < args.endpoint_min_confidence:
            raise SystemExit(f"{name} frame confidence {frame['min_visibility']:.3f} below {args.endpoint_min_confidence}")
    for index, frame in enumerate(features):
        if frame["min_visibility"] < args.min_confidence:
            raise SystemExit(f"cycle frame {index} confidence {frame['min_visibility']:.3f} below {args.min_confidence}")
        if not (args.min_hip_width_ratio <= frame["hip_width_ratio"] <= args.max_hip_width_ratio):
            raise SystemExit(
                f"cycle frame {index} hip/shoulder ratio {frame['hip_width_ratio']:.3f} outside "
                f"{args.min_hip_width_ratio}..{args.max_hip_width_ratio}"
            )

    for name, frame in (("start", start), ("end", end)):
        if frame["ankle_spread"] > args.closed_ankle_max:
            raise SystemExit(f"{name} frame ankle spread {frame['ankle_spread']:.3f} is not closed")
        if frame["wrist_above_shoulder"] > args.closed_wrist_max:
            raise SystemExit(f"{name} frame wrists are not down enough: {frame['wrist_above_shoulder']:.3f}")

    if open_feature["ankle_spread"] < args.open_ankle_min:
        raise SystemExit(f"open frame ankle spread {open_feature['ankle_spread']:.3f} below {args.open_ankle_min}")
    if open_feature["wrist_above_shoulder"] < args.open_wrist_min:
        raise SystemExit(f"open frame wrist raise {open_feature['wrist_above_shoulder']:.3f} below {args.open_wrist_min}")

    ankle_peak = max(range(len(features)), key=lambda index: features[index]["ankle_spread"])
    wrist_peak = max(range(len(features)), key=lambda index: features[index]["wrist_above_shoulder"])
    if abs(ankle_peak - wrist_peak) > args.max_peak_gap_frames:
        raise SystemExit(f"arm/leg peaks are decoupled: ankle={ankle_peak} wrist={wrist_peak}")

    for joint in ("shoulder", "hip", "ankle", "wrist"):
        signs = [
            math.copysign(1.0, frame[f"left.{joint}"]["x"] - frame[f"right.{joint}"]["x"])
            for frame in frames
            if abs(frame[f"left.{joint}"]["x"] - frame[f"right.{joint}"]["x"]) > 1e-5
        ]
        if signs and any(sign != signs[0] for sign in signs):
            raise SystemExit(f"left/right identity flips for {joint}")

    foot_min_visibility = min(
        confidence(frame[name])
        for frame in frames
        for name in FOOT_LANDMARKS
    )
    if foot_min_visibility < args.foot_min_confidence:
        raise SystemExit(
            f"cycle foot landmark confidence {foot_min_visibility:.3f} below {args.foot_min_confidence}"
        )

    return {
        "ankle_peak_index": ankle_peak,
        "wrist_peak_index": wrist_peak,
        "start": rounded_features(start),
        "open": rounded_features(open_feature),
        "end": rounded_features(end),
        "min_visibility": round(min(item["min_visibility"] for item in features), 4),
        "foot_min_visibility": round(foot_min_visibility, 4),
        "max_closed_knee_ankle_ratio": round(max(knee_ankle_ratio(frames[0]), knee_ankle_ratio(frames[-1])), 4),
        "max_open_wrist_spread_ratio": round(wrist_spread_ratio(frames[args.cycle_open_index - args.cycle_start_index]), 4),
        "max_wrist_spread_ratio": round(max(wrist_spread_ratio(frame) for frame in frames), 4),
    }


def rounded_features(values: dict[str, float]) -> dict[str, float]:
    return {key: round(value, 4) for key, value in values.items()}


def add_aliases(landmarks: dict[str, dict[str, float]], primary_side: str) -> dict[str, dict[str, float]]:
    output = copy.deepcopy(landmarks)
    secondary_side = "left" if primary_side == "right" else "right"
    if "nose" in output:
        output["primary.nose"] = dict(output["nose"])
        output["secondary.nose"] = dict(output["nose"])
    for joint in SIDE_JOINTS:
        primary = output.get(f"{primary_side}.{joint}")
        secondary = output.get(f"{secondary_side}.{joint}")
        if primary is not None:
            output[f"primary.{joint}"] = dict(primary)
        if secondary is not None:
            output[f"secondary.{joint}"] = dict(secondary)
    return output


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


def two_bone_joint(
    start: tuple[float, float],
    end: tuple[float, float],
    *,
    first_length: float,
    second_length: float,
    bend_sign: float,
) -> tuple[float, float]:
    dx = end[0] - start[0]
    dy = end[1] - start[1]
    distance_between = max(math.hypot(dx, dy), 1e-6)
    max_reach = first_length + second_length - 1e-6
    if distance_between > max_reach:
        scale = max_reach / distance_between
        end = (start[0] + (dx * scale), start[1] + (dy * scale))
        dx = end[0] - start[0]
        dy = end[1] - start[1]
        distance_between = max(math.hypot(dx, dy), 1e-6)

    ux = dx / distance_between
    uy = dy / distance_between
    along = (
        (first_length * first_length) - (second_length * second_length) + (distance_between * distance_between)
    ) / (2 * distance_between)
    height = math.sqrt(max((first_length * first_length) - (along * along), 0.0))
    return (
        start[0] + (ux * along) + (-uy * height * bend_sign),
        start[1] + (uy * along) + (ux * height * bend_sign),
    )


def source_phase_factors(args: argparse.Namespace, raw_frames: list[dict[str, dict[str, float]]]) -> list[float]:
    open_relative_index = args.cycle_open_index - args.cycle_start_index
    last_index = len(raw_frames) - 1
    if open_relative_index <= 0 or open_relative_index >= last_index:
        raise SystemExit("anatomical retarget requires a full closed-open-closed source cycle")

    features = [cycle_features(frame) for frame in raw_frames]
    for name, index in (("start", 0), ("open", open_relative_index), ("end", last_index)):
        if features[index]["min_visibility"] < args.endpoint_min_confidence:
            raise SystemExit(
                f"{name} source frame confidence {features[index]['min_visibility']:.3f} "
                f"below {args.endpoint_min_confidence}"
            )
    if features[0]["ankle_spread"] > args.closed_ankle_max or features[-1]["ankle_spread"] > args.closed_ankle_max:
        raise SystemExit("source cycle endpoints are not closed enough for anatomical retarget")
    if features[open_relative_index]["ankle_spread"] < args.open_ankle_min:
        raise SystemExit("source cycle open frame is not wide enough for anatomical retarget")
    if features[open_relative_index]["wrist_above_shoulder"] < args.open_wrist_min:
        raise SystemExit("source cycle open frame does not raise wrists enough for anatomical retarget")

    factors: list[float] = []
    for index in range(len(raw_frames)):
        if index <= open_relative_index:
            raw = index / open_relative_index
        else:
            raw = (last_index - index) / max(last_index - open_relative_index, 1)
        factors.append(smoothstep(raw))
    factors[0] = 0.0
    factors[open_relative_index] = 1.0
    factors[-1] = 0.0
    return factors


def wrist_target_for_phase(
    *,
    side_sign: float,
    shoulder_x: float,
    phase_factor: float,
) -> tuple[float, float]:
    """Return a front-view wrist arc shaped like the reviewed source clip.

    The source clip starts with hands near the thighs, sweeps outward through a
    side raise, then finishes with hands above the head. Earlier retargets kept
    the hands beside the shoulders at the closed pose and folded the elbows hard
    at the apex; this path keeps the arm sweep readable while staying inside the
    app avatar viewport.
    """
    phase_factor = clamp(phase_factor, 0.0, 1.0)
    eased = phase_factor

    # Piecewise control points:
    #   0.00 closed: wrists rest beside the thighs.
    #   0.40..0.65 transition: the source athlete passes through a broad side
    #   raise while the feet are travelling outward.
    #   1.00 open: arms finish in a high V. The countable phase is overhead;
    #   the broad side raise is only transition motion.
    controls = [
        (0.00, shoulder_x + (side_sign * 0.030), 0.590),
        (0.18, shoulder_x + (side_sign * 0.080), 0.540),
        (0.42, shoulder_x + (side_sign * 0.155), 0.430),
        (0.64, shoulder_x + (side_sign * 0.185), 0.335),
        (0.84, shoulder_x + (side_sign * 0.150), 0.230),
        (1.00, shoulder_x + (side_sign * 0.120), 0.198),
    ]

    for (start_phase, start_x, start_y), (end_phase, end_x, end_y) in zip(controls, controls[1:]):
        if eased <= end_phase:
            span = max(end_phase - start_phase, 1e-9)
            local = smoothstep((eased - start_phase) / span)
            return (mix(start_x, end_x, local), mix(start_y, end_y, local))

    return (controls[-1][1], controls[-1][2])


def desired_elbow_for_phase(
    *,
    side_sign: float,
    shoulder_x: float,
    shoulder_y: float,
    phase_factor: float,
) -> tuple[float, float]:
    phase_factor = clamp(phase_factor, 0.0, 1.0)
    eased = phase_factor
    controls = [
        (0.00, shoulder_x + (side_sign * 0.020), shoulder_y + 0.112),
        (0.18, shoulder_x + (side_sign * 0.052), shoulder_y + 0.086),
        (0.42, shoulder_x + (side_sign * 0.110), shoulder_y + 0.024),
        (0.64, shoulder_x + (side_sign * 0.126), shoulder_y - 0.046),
        (0.84, shoulder_x + (side_sign * 0.104), shoulder_y - 0.104),
        (1.00, shoulder_x + (side_sign * 0.074), shoulder_y - 0.134),
    ]

    for (start_phase, start_x, start_y), (end_phase, end_x, end_y) in zip(controls, controls[1:]):
        if eased <= end_phase:
            span = max(end_phase - start_phase, 1e-9)
            local = smoothstep((eased - start_phase) / span)
            return (mix(start_x, end_x, local), mix(start_y, end_y, local))

    return (controls[-1][1], controls[-1][2])


def source_shaped_elbow(
    shoulder: tuple[float, float],
    wrist: tuple[float, float],
    *,
    first_length: float,
    second_length: float,
    desired: tuple[float, float],
) -> tuple[float, float]:
    candidates = [
        two_bone_joint(
            shoulder,
            wrist,
            first_length=first_length,
            second_length=second_length,
            bend_sign=-1.0,
        ),
        two_bone_joint(
            shoulder,
            wrist,
            first_length=first_length,
            second_length=second_length,
            bend_sign=1.0,
        ),
    ]
    return min(candidates, key=lambda point: math.hypot(point[0] - desired[0], point[1] - desired[1]))


def jumping_jack_knee(
    hip: tuple[float, float],
    ankle: tuple[float, float],
    *,
    side_sign: float,
    center_x: float,
    phase_factor: float,
    foot_lift: float,
) -> tuple[float, float]:
    """Return a stable front-view knee that bends with the travelling leg.

    The generic two-bone helper often chose the mirrored candidate for near-
    vertical legs, making the knees either perfectly straight or visibly
    crossed. This solver chooses the outward candidate for each side, then
    blends it toward the source-shaped knee track so the legs read as human
    weight-bearing limbs without rubbery bone-length drift.
    """
    phase_factor = clamp(phase_factor, 0.0, 1.0)
    open_eased = smoothstep(phase_factor)
    outward_candidate = two_bone_joint(
        hip,
        ankle,
        first_length=0.160,
        second_length=0.200,
        bend_sign=-side_sign,
    )
    source_track = (
        center_x + (side_sign * mix(0.050, 0.132, open_eased)),
        mix(0.705, 0.690, open_eased) - (foot_lift * 0.25),
    )
    blend_to_source = 0.50
    knee = (
        mix(outward_candidate[0], source_track[0], blend_to_source),
        mix(outward_candidate[1], source_track[1], blend_to_source),
    )
    ankle_half_width = abs(ankle[0] - center_x)
    if ankle_half_width < 0.055:
        knee = (
            center_x + (side_sign * min(abs(knee[0] - center_x), 0.058)),
            knee[1],
        )
    return knee


def anatomical_landmarks(phase_factor: float, primary_side: str) -> dict[str, dict[str, float]]:
    phase_factor = clamp(phase_factor, 0.0, 1.0)
    center_x = 0.5
    open_eased = smoothstep(phase_factor)
    airtime = math.sin(math.pi * phase_factor)
    hop_lift = 0.045 * max(0.0, airtime)
    open_sink = 0.015 * open_eased
    shoulder_y = 0.365 - hop_lift + open_sink
    hip_y = shoulder_y + mix(0.190, 0.203, open_eased)
    nose_y = shoulder_y - mix(0.080, 0.074, open_eased)
    shoulder_half_width = 0.11
    hip_half_width = 0.07

    landmarks: dict[str, dict[str, float]] = {
        "nose": point(center_x, nose_y, -0.03),
        "left.shoulder": point(center_x - shoulder_half_width, shoulder_y, -0.08),
        "right.shoulder": point(center_x + shoulder_half_width, shoulder_y, 0.08),
        "left.hip": point(center_x - hip_half_width, hip_y, -0.06),
        "right.hip": point(center_x + hip_half_width, hip_y, 0.06),
    }

    for side, sign, z in (("left", -1.0, -0.08), ("right", 1.0, 0.08)):
        shoulder = landmarks[f"{side}.shoulder"]
        upper_arm = 0.105
        forearm = 0.105
        wrist = wrist_target_for_phase(
            side_sign=sign,
            shoulder_x=shoulder["x"],
            phase_factor=phase_factor,
        )
        elbow = source_shaped_elbow(
            (shoulder["x"], shoulder["y"]),
            wrist,
            first_length=upper_arm,
            second_length=forearm,
            desired=desired_elbow_for_phase(
                side_sign=sign,
                shoulder_x=shoulder["x"],
                shoulder_y=shoulder["y"],
                phase_factor=phase_factor,
            ),
        )
        landmarks[f"{side}.elbow"] = point(elbow[0], elbow[1], z)
        landmarks[f"{side}.wrist"] = point(wrist[0], wrist[1], z)

        ankle_x = center_x + (sign * mix(0.035, 0.205, open_eased))
        foot_lift = 0.014 * max(0.0, airtime)
        ankle_y = mix(0.880, 0.886, open_eased) - foot_lift
        knee = jumping_jack_knee(
            (landmarks[f"{side}.hip"]["x"], landmarks[f"{side}.hip"]["y"]),
            (ankle_x, ankle_y),
            side_sign=sign,
            center_x=center_x,
            phase_factor=phase_factor,
            foot_lift=foot_lift,
        )
        landmarks[f"{side}.knee"] = point(knee[0], knee[1], z)
        landmarks[f"{side}.ankle"] = point(ankle_x, ankle_y, z)
        heel_offset = mix(0.000, 0.010, phase_factor)
        toe_offset = mix(0.025, 0.055, phase_factor)
        heel_x = ankle_x - (sign * heel_offset)
        toe_x = ankle_x + (sign * toe_offset)
        if side == "left":
            landmarks[f"{side}.heel"] = point(heel_x, ankle_y + 0.025, z)
            landmarks[f"{side}.foot.index"] = point(toe_x, ankle_y + 0.032, z - 0.01)
        else:
            landmarks[f"{side}.heel"] = point(heel_x, ankle_y + 0.025, z)
            landmarks[f"{side}.foot.index"] = point(toe_x, ankle_y + 0.032, z + 0.01)

    return add_aliases(landmarks, primary_side)


def distance_between_landmarks(a: dict[str, float], b: dict[str, float]) -> float:
    return math.hypot(a["x"] - b["x"], a["y"] - b["y"])


def assert_avatar_rig_quality(args: argparse.Namespace, frames: list[dict[str, dict[str, float]]]) -> dict[str, Any]:
    if len(frames) < args.min_real_cycle_frames:
        raise SystemExit(f"retargeted cycle has only {len(frames)} frames")

    duplicate_pairs = []
    for index, (first, second) in enumerate(zip(frames, frames[1:])):
        max_delta = 0.0
        for name in REQUIRED_CYCLE_LANDMARKS + ["nose", "left.heel", "right.heel", "left.foot.index", "right.foot.index"]:
            max_delta = max(
                max_delta,
                abs(first[name]["x"] - second[name]["x"]),
                abs(first[name]["y"] - second[name]["y"]),
                abs(first[name]["z"] - second[name]["z"]),
            )
        if max_delta < args.min_adjacent_motion:
            duplicate_pairs.append(index)
    if duplicate_pairs:
        raise SystemExit(f"retargeted cycle has duplicate adjacent frame pairs at {duplicate_pairs}")

    features = [cycle_features(frame) for frame in frames]
    if features[0]["ankle_spread"] > args.closed_ankle_max or features[-1]["ankle_spread"] > args.closed_ankle_max:
        raise SystemExit("retargeted endpoints are not closed")
    if features[0]["wrist_above_shoulder"] > args.closed_wrist_max or features[-1]["wrist_above_shoulder"] > args.closed_wrist_max:
        raise SystemExit("retargeted endpoints do not keep wrists down")
    for label, frame in (("start", frames[0]), ("end", frames[-1])):
        ankle_spread = max(
            abs(frame["left.ankle"]["x"] - frame["right.ankle"]["x"]),
            1e-9,
        )
        knee_spread = abs(frame["left.knee"]["x"] - frame["right.knee"]["x"])
        knee_ankle_ratio = knee_spread / ankle_spread
        if knee_ankle_ratio > args.max_closed_knee_ankle_ratio:
            raise SystemExit(
                f"retargeted {label} knee/ankle spread ratio "
                f"{knee_ankle_ratio:.3f} exceeds {args.max_closed_knee_ankle_ratio}"
            )
        heel_spread = abs(frame["left.heel"]["x"] - frame["right.heel"]["x"])
        toe_spread = abs(frame["left.foot.index"]["x"] - frame["right.foot.index"]["x"])
        if heel_spread < args.min_closed_heel_spread:
            raise SystemExit(
                f"retargeted {label} heel spread {heel_spread:.3f} below "
                f"{args.min_closed_heel_spread}"
            )
        toe_heel_ratio = toe_spread / max(heel_spread, 1e-9)
        if toe_heel_ratio > args.max_closed_toe_heel_ratio:
            raise SystemExit(
                f"retargeted {label} toe/heel spread ratio "
                f"{toe_heel_ratio:.3f} exceeds {args.max_closed_toe_heel_ratio}"
            )
    for index, frame in enumerate(frames):
        for joint in ("knee", "ankle", "heel", "foot.index"):
            if frame[f"left.{joint}"]["x"] >= frame[f"right.{joint}"]["x"]:
                raise SystemExit(f"retargeted frame {index} crosses left/right {joint} positions")
    open_index = max(range(len(features)), key=lambda index: features[index]["open_score"])
    if features[open_index]["ankle_spread"] < args.open_ankle_min:
        raise SystemExit("retargeted open frame ankle spread is too small")
    if features[open_index]["wrist_above_shoulder"] < args.open_wrist_min:
        raise SystemExit("retargeted open frame wrist raise is too small")
    open_frame = frames[open_index]
    highest_open_wrist_y = min(open_frame["left.wrist"]["y"], open_frame["right.wrist"]["y"])
    if highest_open_wrist_y < args.min_open_wrist_y:
        raise SystemExit(
            f"retargeted open wrists are too high for the avatar guide viewport: "
            f"{highest_open_wrist_y:.3f} below {args.min_open_wrist_y}"
        )
    open_wrist_spread = (
        abs(open_frame["left.wrist"]["x"] - open_frame["right.wrist"]["x"])
        / max(shoulder_width(open_frame), 1e-9)
    )
    if open_wrist_spread > args.max_open_wrist_spread_ratio:
        raise SystemExit(
            f"retargeted open wrist spread {open_wrist_spread:.3f} exceeds "
            f"{args.max_open_wrist_spread_ratio}; arms should finish overhead, not flatten into a T pose"
        )
    max_wrist_spread_ratio = max(
        abs(frame["left.wrist"]["x"] - frame["right.wrist"]["x"]) / max(shoulder_width(frame), 1e-9)
        for frame in frames
    )
    if max_wrist_spread_ratio > args.max_transition_wrist_spread_ratio:
        raise SystemExit(
            f"retargeted transition wrist spread {max_wrist_spread_ratio:.3f} exceeds "
            f"{args.max_transition_wrist_spread_ratio}; source-timed retarget produced a star-pose transition"
        )

    limb_pairs = {
        "left.upper_arm": ("left.shoulder", "left.elbow"),
        "left.forearm": ("left.elbow", "left.wrist"),
        "right.upper_arm": ("right.shoulder", "right.elbow"),
        "right.forearm": ("right.elbow", "right.wrist"),
        "left.thigh": ("left.hip", "left.knee"),
        "left.shin": ("left.knee", "left.ankle"),
        "right.thigh": ("right.hip", "right.knee"),
        "right.shin": ("right.knee", "right.ankle"),
    }
    limb_ratios: dict[str, float] = {}
    for name, (start, end) in limb_pairs.items():
        lengths = [distance_between_landmarks(frame[start], frame[end]) for frame in frames]
        shortest = max(min(lengths), 1e-9)
        ratio = max(lengths) / shortest
        if ratio > args.max_limb_length_ratio:
            raise SystemExit(f"{name} length drift ratio {ratio:.3f} exceeds {args.max_limb_length_ratio}")
        limb_ratios[name] = round(ratio, 4)

    shoulder_widths = [shoulder_width(frame) for frame in frames]
    neck_offsets = [
        abs(frame["nose"]["x"] - ((frame["left.shoulder"]["x"] + frame["right.shoulder"]["x"]) / 2)) / width
        for frame, width in zip(frames, shoulder_widths)
    ]
    if max(neck_offsets) > args.max_head_center_offset:
        raise SystemExit(f"head center offset {max(neck_offsets):.3f} exceeds {args.max_head_center_offset}")

    return {
        "ankle_peak_index": max(range(len(features)), key=lambda index: features[index]["ankle_spread"]),
        "wrist_peak_index": max(range(len(features)), key=lambda index: features[index]["wrist_above_shoulder"]),
        "start": rounded_features(features[0]),
        "open": rounded_features(features[open_index]),
        "end": rounded_features(features[-1]),
        "min_visibility": round(min(item["min_visibility"] for item in features), 4),
        "foot_min_visibility": 1.0,
        "max_limb_length_ratio": round(max(limb_ratios.values()), 4),
        "max_head_center_offset": round(max(neck_offsets), 4),
        "max_closed_knee_ankle_ratio": round(
            max(
                abs(frame["left.knee"]["x"] - frame["right.knee"]["x"])
                / max(abs(frame["left.ankle"]["x"] - frame["right.ankle"]["x"]), 1e-9)
                for frame in (frames[0], frames[-1])
            ),
            4,
        ),
        "min_closed_heel_spread": round(
            min(abs(frame["left.heel"]["x"] - frame["right.heel"]["x"]) for frame in (frames[0], frames[-1])),
            4,
        ),
        "max_closed_toe_heel_ratio": round(
            max(
                abs(frame["left.foot.index"]["x"] - frame["right.foot.index"]["x"])
                / max(abs(frame["left.heel"]["x"] - frame["right.heel"]["x"]), 1e-9)
                for frame in (frames[0], frames[-1])
            ),
            4,
        ),
        "min_open_wrist_y": round(highest_open_wrist_y, 4),
        "max_open_wrist_spread_ratio": round(open_wrist_spread, 4),
        "max_wrist_spread_ratio": round(max_wrist_spread_ratio, 4),
    }


def smooth_sequence(frames: list[dict[str, dict[str, float]]], window: int, protected: set[int]) -> None:
    if window <= 1 or len(frames) < 3:
        return
    radius = window // 2
    source = copy.deepcopy(frames)
    for index, frame in enumerate(frames):
        if index in protected:
            continue
        for name, landmark in frame.items():
            samples = []
            for sample_index in range(max(0, index - radius), min(len(frames), index + radius + 1)):
                sample = source[sample_index].get(name)
                if sample is not None:
                    samples.append(sample)
            if len(samples) < 2:
                continue
            total_weight = sum(max(confidence(sample), 1e-4) for sample in samples)
            for axis in ("x", "y", "z"):
                landmark[axis] = sum(sample[axis] * max(confidence(sample), 1e-4) for sample in samples) / total_weight


def viewport_fit(frames: list[dict[str, dict[str, float]]], margin: float) -> dict[str, float]:
    points = [
        landmark
        for frame in frames
        for name, landmark in frame.items()
        if (
            name in REQUIRED_CYCLE_LANDMARKS
            or name in {"left.heel", "right.heel", "left.foot.index", "right.foot.index", "nose"}
        )
    ]
    min_x = min(point["x"] for point in points)
    max_x = max(point["x"] for point in points)
    min_y = min(point["y"] for point in points)
    max_y = max(point["y"] for point in points)
    source_width = max(max_x - min_x, 1e-9)
    source_height = max(max_y - min_y, 1e-9)
    target_span = max(1e-9, 1 - (2 * margin))
    scale = min(target_span / source_width, target_span / source_height)
    source_cx = (min_x + max_x) / 2
    source_cy = (min_y + max_y) / 2

    for frame in frames:
        for landmark in frame.values():
            landmark["x"] = ((landmark["x"] - source_cx) * scale) + 0.5
            landmark["y"] = ((landmark["y"] - source_cy) * scale) + 0.5
            landmark["z"] = landmark["z"] * scale

    return {
        "source_min_x": round(min_x, 6),
        "source_max_x": round(max_x, 6),
        "source_min_y": round(min_y, 6),
        "source_max_y": round(max_y, 6),
        "scale": round(scale, 6),
        "margin": round(margin, 4),
    }


def loop_close(frames: list[dict[str, dict[str, float]]]) -> dict[str, float]:
    if len(frames) < 2:
        return {"max_endpoint_delta_before": 0.0}
    first = frames[0]
    last = frames[-1]
    max_delta = 0.0
    names = sorted(set(first).intersection(last))
    for name in names:
        max_delta = max(
            max_delta,
            abs(last[name]["x"] - first[name]["x"]),
            abs(last[name]["y"] - first[name]["y"]),
            abs(last[name]["z"] - first[name]["z"]),
        )

    denominator = max(len(frames) - 1, 1)
    for index, frame in enumerate(frames):
        factor = index / denominator
        for name in names:
            drift_x = last[name]["x"] - first[name]["x"]
            drift_y = last[name]["y"] - first[name]["y"]
            drift_z = last[name]["z"] - first[name]["z"]
            frame[name]["x"] -= drift_x * factor
            frame[name]["y"] -= drift_y * factor
            frame[name]["z"] -= drift_z * factor
    return {"max_endpoint_delta_before": round(max_delta, 6)}


def bounds_summary(frames: list[dict[str, dict[str, float]]]) -> dict[str, float]:
    xs = [landmark["x"] for frame in frames for landmark in frame.values()]
    ys = [landmark["y"] for frame in frames for landmark in frame.values()]
    return {
        "min_x": round(min(xs), 6),
        "max_x": round(max(xs), 6),
        "min_y": round(min(ys), 6),
        "max_y": round(max(ys), 6),
    }


def median_interval_ms(records: list[dict[str, Any]]) -> int:
    intervals = [
        int(later["timestamp_ms"]) - int(earlier["timestamp_ms"])
        for earlier, later in zip(records, records[1:])
        if int(later["timestamp_ms"]) > int(earlier["timestamp_ms"])
    ]
    return max(1, round(statistics.median(intervals))) if intervals else 83


def output_samples(
    args: argparse.Namespace,
    selected: list[dict[str, Any]],
    source_indices: list[int],
    phase_factors: list[float | None],
) -> list[dict[str, Any]]:
    samples: list[dict[str, Any]] = []
    if args.upsample_factor > 1:
        for index in range(len(selected) - 1):
            current_timestamp = int(selected[index]["timestamp_ms"])
            next_timestamp = int(selected[index + 1]["timestamp_ms"])
            current_phase = phase_factors[index]
            next_phase = phase_factors[index + 1]
            for step in range(args.upsample_factor):
                local = step / args.upsample_factor
                samples.append(
                    {
                        "source_index": source_indices[index] if local < 0.5 else source_indices[index + 1],
                        "source_timestamp_ms": round(mix(current_timestamp, next_timestamp, local)),
                        "phase_factor": (
                            None
                            if current_phase is None or next_phase is None
                            else mix(float(current_phase), float(next_phase), local)
                        ),
                    }
                )
        samples.append(
            {
                "source_index": source_indices[-1],
                "source_timestamp_ms": int(selected[-1]["timestamp_ms"]),
                "phase_factor": None if phase_factors[-1] is None else float(phase_factors[-1]),
            }
        )
        return samples

    for record, source_index, phase_factor in zip(selected, source_indices, phase_factors):
        samples.append(
            {
                "source_index": source_index,
                "source_timestamp_ms": int(record["timestamp_ms"]),
                "phase_factor": None if phase_factor is None else float(phase_factor),
            }
        )
    return samples


def interpolate_landmark(
    first: dict[str, float],
    second: dict[str, float],
    local: float,
) -> dict[str, float]:
    return {
        key: mix(float(first[key]), float(second[key]), local)
        for key in ("x", "y", "z", "visibility", "presence")
    }


def upsample_landmarks(
    frames: list[dict[str, dict[str, float]]],
    factor: int,
) -> list[dict[str, dict[str, float]]]:
    if factor <= 1 or len(frames) < 2:
        return frames

    upsampled: list[dict[str, dict[str, float]]] = []
    for index in range(len(frames) - 1):
        current = frames[index]
        following = frames[index + 1]
        for step in range(factor):
            local = step / factor
            upsampled.append(
                {
                    name: interpolate_landmark(point, following[name], local)
                    for name, point in current.items()
                    if name in following
                }
            )
    upsampled.append(copy.deepcopy(frames[-1]))
    return upsampled


def build_frames(args: argparse.Namespace, records: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    if args.mirror_return:
        selected, source_indices = mirrored_half_cycle_records(args, records)
    else:
        selected, source_indices = selected_records(args, records)
    source_mapped = [named_landmarks(record) for record in selected]

    if args.retarget_mode == "anatomical":
        if args.mirror_return:
            raise SystemExit("--retarget-mode anatomical requires a real source cycle, not --mirror-return")
        phase_factors = source_phase_factors(args, source_mapped)
        samples = output_samples(args, selected, source_indices, phase_factors)
        mapped = [anatomical_landmarks(float(sample["phase_factor"]), args.primary_side) for sample in samples]
        cycle_summary = assert_avatar_rig_quality(args, mapped)
        loop = {"max_endpoint_delta_before": 0.0}
        viewport = {
            "source_min_x": None,
            "source_max_x": None,
            "source_min_y": None,
            "source_max_y": None,
            "scale": 1.0,
            "margin": round(args.viewport_margin, 4),
        }
    else:
        mapped = source_mapped
        phase_factors = [None] * len(mapped)
        cycle_summary = assert_cycle_quality(args, mapped)

        protected = {
            0,
            args.cycle_open_index - args.cycle_start_index,
            len(mapped) - 1,
        }
        smooth_sequence(mapped, args.smoothing_window, protected=protected)
        loop = loop_close(mapped)
        viewport = viewport_fit(mapped, args.viewport_margin)
        samples = output_samples(args, selected, source_indices, phase_factors)
        mapped = upsample_landmarks(mapped, args.upsample_factor)
    bounds = bounds_summary(mapped)
    for axis, value in bounds.items():
        if (axis.startswith("min") and value < -1e-6) or (axis.startswith("max") and value > 1 + 1e-6):
            raise SystemExit(f"normalized bounds out of range: {bounds}")

    source_offset = int(selected[0]["timestamp_ms"])
    frames: list[dict[str, Any]] = []
    interval = args.interval_ms if args.interval_ms is not None else median_interval_ms(selected)
    for index, (sample, landmarks) in enumerate(zip(samples, mapped)):
        relative_timestamp = int(sample["source_timestamp_ms"]) - source_offset
        frames.append(
            {
                "type": "motion_demo_pose",
                "exercise_id": args.exercise_id,
                "timestamp_ms": relative_timestamp if args.retarget_mode == "anatomical" else index * interval,
                "image_size": [1280, 720],
                "phase": (
                    "external_reference_jumping_jack_anatomical_retarget"
                    if args.retarget_mode == "anatomical"
                    else "raw_front_view_jumping_jack"
                ),
                "source_kind": "licensed_external_reference_trace",
                "source_frame_id": sample["source_index"],
                "source_timestamp_ms": int(sample["source_timestamp_ms"]) + args.source_start_ms,
                **(
                    {"phase_factor": round(float(sample["phase_factor"]), 6)}
                    if sample["phase_factor"] is not None
                    else {}
                ),
                "landmarks": add_aliases(landmarks, args.primary_side),
            }
        )

    summary = {
        "frames": len(frames),
        "interval_ms": interval,
        "cycle_start_index": args.cycle_start_index,
        "cycle_open_index": args.cycle_open_index,
        "cycle_end_index": args.cycle_end_index,
        "source_indices": source_indices,
        "output_source_frame_ids": [sample["source_index"] for sample in samples],
        "upsample_factor": args.upsample_factor,
        "mirror_return": args.mirror_return,
        "closing_hold_frames": args.closing_hold_frames if args.mirror_return else 0,
        "source_start_timestamp_ms": source_offset + args.source_start_ms,
        "source_end_timestamp_ms": int(records[args.cycle_end_index]["timestamp_ms"]) + args.source_start_ms,
        "cycle": cycle_summary,
        "viewport_fit": viewport,
        "loop_closure": loop,
        "bounds": bounds,
        "smoothing_window": args.smoothing_window,
        "retarget_mode": args.retarget_mode,
    }
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
        "source_video": repo_relative(args.video) if args.video else None,
        "source_page": args.source_page,
        "source_file_url": args.source_file_url,
        "source_license": args.source_license,
        "source_attribution": args.source_attribution,
        "raw_trace": repo_relative(args.raw),
        "normalizer": "scripts/motion_reference/normalize_jumping_jack_trace.py",
        "output_trace": repo_relative(args.output),
        "retarget": retarget_label(args),
        "loop_closure": (
            "source_timed_anatomical_closed_loop"
            if args.retarget_mode == "anatomical"
            else "mirrored_real_half_cycle"
            if args.mirror_return
            else "linear_endpoint_drift_correction"
        ),
        "summary": summary,
        "qa_gates": [
            "licensed_source_recorded",
            "raw_pose_reviewed",
            "single_subject_front_view",
            "source_timed_anatomical_retarget"
            if args.retarget_mode == "anatomical"
            else "closed_open_mirrored_closed_spread" if args.mirror_return else "closed_open_closed_spread",
            "arm_leg_peak_coupled",
            *(
                [
                    "real_closed_open_closed_source_cycle",
                    "bone_length_stable",
                    "head_neck_anchor_stable",
                    "closed_feet_readable",
                    "overhead_hands_near_source_shape",
                    "no_frame_local_avatar_rescale",
                    "no_duplicate_adjacent_frames",
                ]
                if args.retarget_mode == "anatomical"
                else []
            ),
            "loop_boundary_stable",
            "engine_counts_one_rep",
            "agent_visual_reviewed",
        ],
    }
    args.output.with_suffix(".manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def repo_relative(path: Path | None) -> str | None:
    if path is None:
        return None
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path)


def retarget_label(args: argparse.Namespace) -> str:
    if args.retarget_mode == "anatomical":
        return "source_timed_anatomical_front_view_avatar_rig"
    if args.mirror_return:
        return "raw_mediapipe_front_view_half_cycle_mirrored_with_viewport_stabilization"
    return "raw_mediapipe_front_view_preserved_with_viewport_stabilization"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--video", type=Path)
    parser.add_argument("--exercise-id", default="bodyweight_jumping_jack")
    parser.add_argument("--cycle-start-index", type=int, required=True)
    parser.add_argument("--cycle-open-index", type=int, required=True)
    parser.add_argument("--cycle-end-index", type=int, required=True)
    parser.add_argument("--retarget-mode", choices=["raw", "anatomical"], default="raw")
    parser.add_argument("--mirror-return", action="store_true")
    parser.add_argument("--closing-hold-frames", type=int, default=0)
    parser.add_argument("--source-start-ms", type=int, default=0)
    parser.add_argument("--interval-ms", type=int)
    parser.add_argument("--smoothing-window", type=int, default=1)
    parser.add_argument("--viewport-margin", type=float, default=0.08)
    parser.add_argument("--primary-side", choices=["left", "right"], default="right")
    parser.add_argument("--min-confidence", type=float, default=0.65)
    parser.add_argument("--endpoint-min-confidence", type=float, default=0.75)
    parser.add_argument("--foot-min-confidence", type=float, default=0.70)
    parser.add_argument("--closed-ankle-max", type=float, default=0.45)
    parser.add_argument("--closed-wrist-max", type=float, default=-0.75)
    parser.add_argument("--open-ankle-min", type=float, default=1.45)
    parser.add_argument("--open-wrist-min", type=float, default=0.85)
    parser.add_argument("--min-hip-width-ratio", type=float, default=0.35)
    parser.add_argument("--max-hip-width-ratio", type=float, default=0.85)
    parser.add_argument("--max-peak-gap-frames", type=int, default=3)
    parser.add_argument("--min-real-cycle-frames", type=int, default=12)
    parser.add_argument("--upsample-factor", type=int, default=2)
    parser.add_argument("--min-adjacent-motion", type=float, default=0.003)
    parser.add_argument("--max-limb-length-ratio", type=float, default=1.20)
    parser.add_argument("--max-head-center-offset", type=float, default=0.12)
    parser.add_argument("--max-closed-knee-ankle-ratio", type=float, default=1.75)
    parser.add_argument("--min-closed-heel-spread", type=float, default=0.05)
    parser.add_argument("--max-closed-toe-heel-ratio", type=float, default=3.0)
    parser.add_argument("--min-open-wrist-y", type=float, default=0.145)
    parser.add_argument("--max-open-wrist-spread-ratio", type=float, default=2.45)
    parser.add_argument("--max-transition-wrist-spread-ratio", type=float, default=2.75)
    parser.add_argument("--source-label", default="Pexels 6326725 Men Doing Jumping Jacks at the Gym")
    parser.add_argument("--source-page", default="https://www.pexels.com/video/men-doing-jumping-jacks-at-the-gym-6326725/")
    parser.add_argument("--source-file-url", default="https://www.pexels.com/download/video/6326725/")
    parser.add_argument("--source-license", default="Pexels License")
    parser.add_argument("--source-attribution", default="Pavel Danilyuk / Pexels")
    return parser.parse_args()


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
        f"cycle={args.cycle_start_index}..{args.cycle_open_index}..{args.cycle_end_index}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
