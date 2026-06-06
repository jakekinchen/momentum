#!/usr/bin/env python3
"""Compile profile-driven canonical exercise traces into motion_demo_pose JSONL."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any, Callable

IMAGE_SIZE = [1280, 720]
SUPPORTED_ARCHETYPES = {
    "bilateral_squat",
    "horizontal_press",
    "static_hold",
}


def landmark(x: float, y: float, z: float = 0.0, visibility: float = 1.0, presence: float = 1.0) -> dict[str, float]:
    return {
        "x": round(float(x), 6),
        "y": round(float(y), 6),
        "z": round(float(z), 6),
        "visibility": float(visibility),
        "presence": float(presence),
    }


def mix(a: float, b: float, factor: float) -> float:
    return a + ((b - a) * factor)


def point_lerp(a: tuple[float, float, float], b: tuple[float, float, float], factor: float) -> dict[str, float]:
    return landmark(mix(a[0], b[0], factor), mix(a[1], b[1], factor), mix(a[2], b[2], factor))


def smoothstep(factor: float) -> float:
    factor = max(0.0, min(1.0, factor))
    return factor * factor * (3 - (2 * factor))


def mirrored_factors(samples_per_half: int, hold_bottom: int = 2, hold_top: int = 2) -> list[float]:
    descent = [smoothstep(index / samples_per_half) for index in range(samples_per_half + 1)]
    ascent = list(reversed(descent[:-1]))
    return ([0.0] * hold_top) + descent + ([1.0] * hold_bottom) + ascent + ([0.0] * hold_top)


def static_factors(frame_count: int) -> list[float]:
    return [0.0] * frame_count


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


def add_side(
    landmarks: dict[str, dict[str, float]],
    prefix: str,
    points: dict[str, tuple[float, float, float] | dict[str, float]],
) -> None:
    for joint, point in points.items():
        if isinstance(point, dict):
            landmarks[f"{prefix}.{joint}"] = dict(point)
        else:
            landmarks[f"{prefix}.{joint}"] = landmark(*point)


def duplicate_primary_to_side(
    landmarks: dict[str, dict[str, float]],
    side: str,
    primary: dict[str, dict[str, float]],
    x_offset: float,
    z_offset: float,
) -> None:
    for joint, point in primary.items():
        if joint == "nose":
            continue
        landmarks[f"{side}.{joint}"] = landmark(
            point["x"] + x_offset,
            point["y"],
            point["z"] + z_offset,
            point["visibility"],
            point["presence"],
        )


def angle_degrees(a: dict[str, float], b: dict[str, float], c: dict[str, float]) -> float:
    bax = a["x"] - b["x"]
    bay = a["y"] - b["y"]
    bcx = c["x"] - b["x"]
    bcy = c["y"] - b["y"]
    dot = (bax * bcx) + (bay * bcy)
    norm_a = max(math.sqrt((bax * bax) + (bay * bay)), 1e-9)
    norm_c = max(math.sqrt((bcx * bcx) + (bcy * bcy)), 1e-9)
    return math.degrees(math.acos(max(-1.0, min(1.0, dot / (norm_a * norm_c)))))


def squat_landmarks(factor: float) -> dict[str, dict[str, float]]:
    primary = {
        "nose": point_lerp((0.620, 0.205, -0.02), (0.475, 0.315, -0.02), factor),
        "shoulder": point_lerp((0.620, 0.300, 0.0), (0.485, 0.420, 0.0), factor),
        "elbow": point_lerp((0.660, 0.425, 0.03), (0.610, 0.495, 0.03), factor),
        "wrist": point_lerp((0.700, 0.550, 0.08), (0.675, 0.555, 0.08), factor),
        "hip": point_lerp((0.620, 0.485, 0.0), (0.505, 0.650, 0.0), factor),
        "knee": point_lerp((0.620, 0.660, 0.02), (0.715, 0.650, 0.02), factor),
        "ankle": landmark(0.620, 0.845, 0.05),
    }
    secondary = {
        "shoulder": landmark(primary["shoulder"]["x"] - 0.055, primary["shoulder"]["y"], -0.16),
        "elbow": point_lerp((0.500, 0.425, -0.16), (0.555, 0.495, -0.16), factor),
        "wrist": point_lerp((0.540, 0.550, -0.16), (0.620, 0.555, -0.16), factor),
        "hip": landmark(primary["hip"]["x"] - 0.055, primary["hip"]["y"], -0.16),
        "knee": point_lerp((0.565, 0.660, -0.14), (0.660, 0.650, -0.14), factor),
        "ankle": landmark(0.565, 0.845, -0.15),
    }

    landmarks = {"nose": dict(primary["nose"])}
    for joint, point in primary.items():
        landmarks[f"primary.{joint}"] = dict(point)
    add_foot(landmarks, "primary", (0.570, 0.862, 0.05), (0.735, 0.862, 0.06))
    add_side(landmarks, "secondary", secondary)
    add_foot(landmarks, "secondary", (0.515, 0.862, -0.15), (0.680, 0.862, -0.14))
    duplicate_primary_to_side(landmarks, "right", primary, x_offset=0.0, z_offset=0.10)
    duplicate_primary_to_side(landmarks, "left", secondary, x_offset=0.0, z_offset=-0.02)
    add_foot(landmarks, "right", (0.570, 0.862, 0.15), (0.735, 0.862, 0.16), (0.620, 0.845, 0.15))
    add_foot(landmarks, "left", (0.515, 0.862, -0.17), (0.680, 0.862, -0.16), (0.565, 0.845, -0.17))
    return landmarks


def pushup_landmarks(factor: float) -> dict[str, dict[str, float]]:
    wrist = (0.645, 0.690, 0.08)
    toe = (0.165, 0.665, 0.04)
    ankle = landmark(0.205, 0.638, 0.04)
    shoulder = point_lerp((0.550, 0.515, 0.0), (0.560, 0.580, 0.0), factor)
    hip = point_lerp((0.384, 0.574, 0.0), (0.390, 0.608, 0.0), factor)
    knee = point_lerp((0.288, 0.608, 0.02), (0.290, 0.624, 0.02), factor)
    primary = {
        "nose": point_lerp((0.655, 0.455, -0.03), (0.650, 0.540, -0.03), factor),
        "shoulder": shoulder,
        "elbow": point_lerp((0.598, 0.603, 0.03), (0.535, 0.630, 0.03), factor),
        "wrist": landmark(*wrist),
        "hip": hip,
        "knee": knee,
        "ankle": dict(ankle),
    }
    secondary = {
        "shoulder": landmark(primary["shoulder"]["x"], primary["shoulder"]["y"] - 0.010, -0.16),
        "elbow": landmark(primary["elbow"]["x"] - 0.025, primary["elbow"]["y"], -0.14),
        "wrist": landmark(wrist[0] - 0.035, wrist[1], -0.12),
        "hip": landmark(primary["hip"]["x"], primary["hip"]["y"] - 0.010, -0.16),
        "knee": landmark(primary["knee"]["x"], primary["knee"]["y"] - 0.010, -0.14),
        "ankle": landmark(ankle["x"], ankle["y"] - 0.010, -0.13),
    }

    landmarks = {"nose": dict(primary["nose"])}
    for joint, point in primary.items():
        landmarks[f"primary.{joint}"] = dict(point)
    add_foot(landmarks, "primary", (ankle["x"], ankle["y"], ankle["z"]), toe)
    add_side(landmarks, "secondary", secondary)
    add_foot(landmarks, "secondary", (ankle["x"], ankle["y"] - 0.010, -0.13), (toe[0], toe[1] - 0.010, -0.12))
    duplicate_primary_to_side(landmarks, "right", primary, x_offset=0.0, z_offset=0.10)
    duplicate_primary_to_side(landmarks, "left", secondary, x_offset=0.0, z_offset=-0.02)
    add_foot(landmarks, "right", (ankle["x"], ankle["y"], 0.14), (toe[0], toe[1], 0.14), (ankle["x"], ankle["y"], 0.14))
    add_foot(landmarks, "left", (ankle["x"], ankle["y"] - 0.010, -0.15), (toe[0], toe[1] - 0.010, -0.14), (ankle["x"], ankle["y"] - 0.010, -0.15))
    return landmarks


def plank_landmarks(_: float) -> dict[str, dict[str, float]]:
    primary = {
        "nose": landmark(0.660, 0.390, -0.03),
        "shoulder": landmark(0.570, 0.465, 0.0),
        "elbow": landmark(0.615, 0.650, 0.03),
        "wrist": landmark(0.670, 0.685, 0.08),
        "hip": landmark(0.380, 0.5575, 0.0),
        "knee": landmark(0.270, 0.6075, 0.02),
        "ankle": landmark(0.190, 0.650, 0.04),
    }
    secondary = {
        "shoulder": landmark(0.570, 0.455, -0.16),
        "elbow": landmark(0.600, 0.650, -0.14),
        "wrist": landmark(0.650, 0.685, -0.12),
        "hip": landmark(0.380, 0.5475, -0.16),
        "knee": landmark(0.270, 0.5975, -0.14),
        "ankle": landmark(0.190, 0.640, -0.13),
    }

    landmarks = {"nose": dict(primary["nose"])}
    for joint, point in primary.items():
        landmarks[f"primary.{joint}"] = dict(point)
    add_foot(landmarks, "primary", (0.190, 0.650, 0.04), (0.165, 0.665, 0.04))
    add_side(landmarks, "secondary", secondary)
    add_foot(landmarks, "secondary", (0.190, 0.640, -0.13), (0.165, 0.655, -0.12))
    duplicate_primary_to_side(landmarks, "right", primary, x_offset=0.0, z_offset=0.10)
    duplicate_primary_to_side(landmarks, "left", secondary, x_offset=0.0, z_offset=-0.02)
    add_foot(landmarks, "right", (0.190, 0.650, 0.14), (0.165, 0.665, 0.14), (0.190, 0.650, 0.14))
    add_foot(landmarks, "left", (0.190, 0.640, -0.15), (0.165, 0.655, -0.14), (0.190, 0.640, -0.15))
    return landmarks


def archetype_function(archetype: str) -> Callable[[float], dict[str, dict[str, float]]]:
    if archetype == "bilateral_squat":
        return squat_landmarks
    if archetype == "horizontal_press":
        return pushup_landmarks
    if archetype == "static_hold":
        return plank_landmarks
    raise SystemExit(f"unsupported archetype: {archetype}")


def factors_for_archetype(archetype: str) -> list[float]:
    if archetype == "static_hold":
        return static_factors(31)
    return mirrored_factors(samples_per_half=24, hold_bottom=3, hold_top=3)


def build_frames(profile: dict[str, Any], interval_ms: int) -> list[dict[str, Any]]:
    exercise_id = profile["exercise_id"]
    archetype = profile["archetype"]
    landmarks_for_factor = archetype_function(archetype)
    frames = []
    for index, factor in enumerate(factors_for_archetype(archetype)):
        frames.append(
            {
                "type": "motion_demo_pose",
                "exercise_id": exercise_id,
                "timestamp_ms": index * interval_ms,
                "image_size": IMAGE_SIZE,
                "phase": f"canonical_{archetype}",
                "source_kind": "canonical_archetype_trace",
                "landmarks": landmarks_for_factor(factor),
            }
        )
    return frames


def summarize(frames: list[dict[str, Any]], archetype: str) -> dict[str, Any]:
    values: list[float] = []
    key = None
    for frame in frames:
        landmarks = frame["landmarks"]
        if archetype == "bilateral_squat":
            key = "primary_knee_angle"
            values.append(angle_degrees(landmarks["primary.hip"], landmarks["primary.knee"], landmarks["primary.ankle"]))
        elif archetype == "horizontal_press":
            key = "primary_elbow_angle"
            values.append(angle_degrees(landmarks["primary.shoulder"], landmarks["primary.elbow"], landmarks["primary.wrist"]))
        elif archetype == "static_hold":
            key = "primary_plank_line_angle"
            values.append(angle_degrees(landmarks["primary.shoulder"], landmarks["primary.hip"], landmarks["primary.ankle"]))

    summary: dict[str, Any] = {"frames": len(frames)}
    if key and values:
        summary[f"min_{key}"] = round(min(values), 2)
        summary[f"max_{key}"] = round(max(values), 2)
    return summary


def write_trace(profile: dict[str, Any], output: Path, interval_ms: int) -> None:
    frames = build_frames(profile, interval_ms)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8") as handle:
        for frame in frames:
            handle.write(json.dumps(frame, separators=(",", ":")) + "\n")

    normalizer = profile.get("normalizer", {})
    manifest = {
        "exercise_id": profile["exercise_id"],
        "source_kind": "canonical_archetype_trace",
        "source_label": f"{profile['archetype']} canonical motion profile",
        "archetype": profile["archetype"],
        "profile_registry": "scripts/motion_reference/exercise_motion_profiles.json",
        "compiler": "scripts/motion_reference/compile_archetype_trace.py",
        "output_trace": str(output),
        "interval_ms": interval_ms,
        "retarget": normalizer.get("retarget"),
        "required_contacts": profile.get("required_contacts", []),
        "required_output_landmarks": profile.get("required_output_landmarks", []),
        "summary": summarize(frames, profile["archetype"]),
        "replacement_plan": "Replace with first_party_trainer_reference_video when captured; keep this trace as the deterministic archetype fallback.",
    }
    output.with_suffix(".manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"motion-reference compiled={output} exercise_id={profile['exercise_id']} frames={len(frames)}")


def load_profiles(path: Path) -> dict[str, dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    return {profile["exercise_id"]: profile for profile in payload.get("profiles", [])}


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profiles", type=Path, default=script_dir / "exercise_motion_profiles.json")
    parser.add_argument("--exercise-id", action="append", dest="exercise_ids", help="exercise id to compile; may repeat")
    parser.add_argument("--all", action="store_true", help="compile every supported profile archetype")
    parser.add_argument("--output-dir", type=Path, default=repo_root / "Sources/CamiFitApp/Resources/MotionDemos")
    parser.add_argument("--interval-ms", type=int, default=100)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    profiles = load_profiles(args.profiles)
    if args.all:
        exercise_ids = [
            exercise_id
            for exercise_id, profile in profiles.items()
            if profile.get("archetype") in SUPPORTED_ARCHETYPES
        ]
    else:
        exercise_ids = args.exercise_ids or []
    if not exercise_ids:
        raise SystemExit("pass --all or at least one --exercise-id")

    for exercise_id in exercise_ids:
        profile = profiles.get(exercise_id)
        if profile is None:
            raise SystemExit(f"unknown exercise id: {exercise_id}")
        if profile.get("archetype") not in SUPPORTED_ARCHETYPES:
            raise SystemExit(f"{exercise_id}: unsupported archetype {profile.get('archetype')}")
        output = args.output_dir / f"{exercise_id}.jsonl"
        write_trace(profile, output, args.interval_ms)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
