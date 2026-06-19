#!/usr/bin/env python3
"""Compile profile-driven canonical exercise traces into motion_demo_pose JSONL."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any, Callable

IMAGE_SIZE = [1280, 720]
PENDING_CAPTURE_STATUSES = {
    "pending_first_party_capture",
    "pending_licensed_reference_clip",
}
SUPPORTED_ARCHETYPES = {
    "bilateral_squat",
    "bodyweight_pike",
    "chest_supported_row",
    "horizontal_press",
    "jumping_jack",
    "lying_tricep_extension",
    "preacher_curl",
    "standing_cable_tricep_extension",
    "standing_reverse_curl",
    "standing_hip_flexion",
    "suspension_tricep_press",
    "static_hold",
}


def repo_relative(path: Path) -> str:
    repo_root = Path(__file__).resolve().parents[2]
    try:
        return str(path.resolve().relative_to(repo_root))
    except ValueError:
        return str(path)


def is_relative_to(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


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


def distance(a: dict[str, float], b: dict[str, float]) -> float:
    dx = a["x"] - b["x"]
    dy = a["y"] - b["y"]
    return math.sqrt((dx * dx) + (dy * dy))


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


def pike_landmarks(factor: float) -> dict[str, dict[str, float]]:
    wrist = landmark(0.680, 0.680, 0.08)
    ankle = landmark(0.200, 0.660, 0.04)
    primary = {
        "nose": point_lerp((0.660, 0.390, -0.03), (0.650, 0.400, -0.03), factor),
        "shoulder": point_lerp((0.560, 0.480, 0.0), (0.580, 0.500, 0.0), factor),
        "elbow": point_lerp((0.620, 0.600, 0.03), (0.630, 0.590, 0.03), factor),
        "wrist": wrist,
        "hip": point_lerp((0.380, 0.560, 0.0), (0.390, 0.300, 0.0), factor),
        "knee": point_lerp((0.290, 0.610, 0.02), (0.300, 0.480, 0.02), factor),
        "ankle": ankle,
    }

    landmarks = {"nose": dict(primary["nose"])}
    add_side(landmarks, "primary", primary)
    duplicate_primary_to_side(landmarks, "right", primary, x_offset=0.0, z_offset=0.10)
    duplicate_primary_to_side(landmarks, "left", primary, x_offset=-0.090, z_offset=-0.12)
    add_foot(landmarks, "primary", (0.200, 0.660, 0.04), (0.165, 0.675, 0.04), (0.200, 0.660, 0.04))
    add_foot(landmarks, "right", (0.200, 0.660, 0.14), (0.165, 0.675, 0.14), (0.200, 0.660, 0.14))
    add_foot(landmarks, "left", (0.110, 0.660, -0.08), (0.075, 0.675, -0.08), (0.110, 0.660, -0.08))
    return landmarks


def jumping_jack_landmarks(factor: float) -> dict[str, dict[str, float]]:
    left_shoulder = landmark(0.390, 0.280, -0.05)
    right_shoulder = landmark(0.610, 0.280, 0.05)
    left_hip = landmark(0.430, 0.520, -0.04)
    right_hip = landmark(0.570, 0.520, 0.04)
    left_ankle = landmark(mix(0.460, 0.280, factor), 0.860, -0.05)
    right_ankle = landmark(mix(0.540, 0.720, factor), 0.860, 0.05)
    left_wrist = landmark(mix(0.405, 0.220, factor), mix(0.610, 0.150, factor), -0.07)
    right_wrist = landmark(mix(0.595, 0.780, factor), mix(0.610, 0.150, factor), 0.07)
    left = {
        "shoulder": left_shoulder,
        "elbow": landmark(mix(0.385, 0.310, factor), mix(0.445, 0.220, factor), -0.06),
        "wrist": left_wrist,
        "hip": left_hip,
        "knee": landmark(mix(0.445, 0.380, factor), 0.700, -0.045),
        "ankle": left_ankle,
    }
    right = {
        "shoulder": right_shoulder,
        "elbow": landmark(mix(0.615, 0.690, factor), mix(0.445, 0.220, factor), 0.06),
        "wrist": right_wrist,
        "hip": right_hip,
        "knee": landmark(mix(0.555, 0.620, factor), 0.700, 0.045),
        "ankle": right_ankle,
    }

    landmarks = {
        "nose": landmark(0.500, 0.160, -0.02),
        "primary.nose": landmark(0.500, 0.160, -0.02),
    }
    add_side(landmarks, "left", left)
    add_side(landmarks, "right", right)
    add_side(landmarks, "primary", right)
    add_foot(
        landmarks,
        "left",
        (left_ankle["x"] - 0.075, left_ankle["y"] + 0.012, left_ankle["z"]),
        (left_ankle["x"] + 0.075, left_ankle["y"] + 0.018, left_ankle["z"] + 0.01),
    )
    add_foot(
        landmarks,
        "right",
        (right_ankle["x"] - 0.015, right_ankle["y"] + 0.012, right_ankle["z"]),
        (right_ankle["x"] + 0.135, right_ankle["y"] + 0.018, right_ankle["z"] + 0.01),
    )
    add_foot(
        landmarks,
        "primary",
        (right_ankle["x"] - 0.015, right_ankle["y"] + 0.012, right_ankle["z"]),
        (right_ankle["x"] + 0.135, right_ankle["y"] + 0.018, right_ankle["z"] + 0.01),
    )
    return landmarks


def standing_hip_flexion_landmarks(factor: float) -> dict[str, dict[str, float]]:
    working = {
        "nose": point_lerp((0.520, 0.170, -0.03), (0.510, 0.190, -0.03), factor),
        "shoulder": point_lerp((0.520, 0.290, 0.0), (0.510, 0.310, 0.0), factor),
        "elbow": point_lerp((0.490, 0.430, 0.03), (0.480, 0.440, 0.03), factor),
        "wrist": point_lerp((0.470, 0.550, 0.08), (0.460, 0.560, 0.08), factor),
        "hip": landmark(0.520, 0.500, 0.0),
        "knee": point_lerp((0.520, 0.690, 0.02), (0.700, 0.540, 0.02), factor),
        "ankle": point_lerp((0.520, 0.860, 0.05), (0.730, 0.650, 0.05), factor),
    }
    stance = {
        "shoulder": landmark(0.460, 0.300, -0.16),
        "elbow": landmark(0.430, 0.440, -0.16),
        "wrist": landmark(0.410, 0.560, -0.16),
        "hip": landmark(0.460, 0.500, -0.16),
        "knee": landmark(0.460, 0.680, -0.16),
        "ankle": landmark(0.460, 0.860, -0.16),
    }

    landmarks = {"nose": dict(working["nose"])}
    for joint, point in working.items():
        landmarks[f"primary.{joint}"] = dict(point)
    add_side(landmarks, "left", working)
    add_foot(landmarks, "primary", (working["ankle"]["x"] - 0.045, working["ankle"]["y"] + 0.012, 0.05), (working["ankle"]["x"] + 0.105, working["ankle"]["y"] + 0.018, 0.06), (working["ankle"]["x"], working["ankle"]["y"], 0.05))
    add_foot(landmarks, "left", (working["ankle"]["x"] - 0.045, working["ankle"]["y"] + 0.012, 0.05), (working["ankle"]["x"] + 0.105, working["ankle"]["y"] + 0.018, 0.06), (working["ankle"]["x"], working["ankle"]["y"], 0.05))
    add_side(landmarks, "right", stance)
    add_foot(landmarks, "right", (0.415, 0.872, -0.16), (0.565, 0.878, -0.15), (0.460, 0.860, -0.16))
    return landmarks


def standing_reverse_curl_landmarks(factor: float) -> dict[str, dict[str, float]]:
    shoulder = landmark(0.520, 0.320, 0.0)
    elbow = landmark(0.490, 0.480, 0.03)
    wrist = landmark(mix(0.500, 0.630, factor), mix(0.720, 0.460, factor), 0.08)
    primary = {
        "nose": landmark(0.525, 0.190, -0.03),
        "shoulder": shoulder,
        "elbow": elbow,
        "wrist": wrist,
        "hip": landmark(0.520, 0.545, 0.0),
        "knee": landmark(0.520, 0.710, 0.02),
        "ankle": landmark(0.520, 0.865, 0.05),
    }

    landmarks = {"nose": dict(primary["nose"])}
    add_side(landmarks, "primary", primary)
    duplicate_primary_to_side(landmarks, "right", primary, x_offset=0.0, z_offset=0.10)
    duplicate_primary_to_side(landmarks, "left", primary, x_offset=-0.090, z_offset=-0.12)
    add_foot(landmarks, "primary", (0.475, 0.877, 0.05), (0.625, 0.883, 0.06), (0.520, 0.865, 0.05))
    add_foot(landmarks, "right", (0.475, 0.877, 0.15), (0.625, 0.883, 0.16), (0.520, 0.865, 0.15))
    add_foot(landmarks, "left", (0.385, 0.877, -0.07), (0.535, 0.883, -0.06), (0.430, 0.865, -0.07))
    return landmarks


def preacher_curl_landmarks(factor: float) -> dict[str, dict[str, float]]:
    shoulder = landmark(0.500, 0.300, 0.0)
    elbow = landmark(0.600, 0.540, 0.03)
    wrist = landmark(mix(0.680, 0.460, factor), mix(0.760, 0.500, factor), 0.08)
    primary = {
        "nose": landmark(0.495, 0.180, -0.03),
        "shoulder": shoulder,
        "elbow": elbow,
        "wrist": wrist,
        "hip": landmark(0.470, 0.590, 0.0),
        "knee": landmark(0.580, 0.720, 0.02),
        "ankle": landmark(0.630, 0.860, 0.05),
    }

    landmarks = {"nose": dict(primary["nose"])}
    add_side(landmarks, "primary", primary)
    duplicate_primary_to_side(landmarks, "right", primary, x_offset=0.0, z_offset=0.10)
    duplicate_primary_to_side(landmarks, "left", primary, x_offset=-0.090, z_offset=-0.12)
    add_foot(landmarks, "primary", (0.585, 0.872, 0.05), (0.735, 0.878, 0.06), (0.630, 0.860, 0.05))
    add_foot(landmarks, "right", (0.585, 0.872, 0.15), (0.735, 0.878, 0.16), (0.630, 0.860, 0.15))
    add_foot(landmarks, "left", (0.495, 0.872, -0.07), (0.645, 0.878, -0.06), (0.540, 0.860, -0.07))
    return landmarks


def chest_supported_row_landmarks(factor: float) -> dict[str, dict[str, float]]:
    left = {
        "nose": landmark(0.430, 0.270, -0.03),
        "shoulder": landmark(0.460, 0.400, 0.0),
        "elbow": landmark(mix(0.550, 0.390, factor), mix(0.560, 0.500, factor), 0.03),
        "wrist": landmark(mix(0.660, 0.500, factor), mix(0.730, 0.550, factor), 0.08),
        "hip": landmark(0.580, 0.600, 0.0),
        "knee": landmark(0.720, 0.710, 0.02),
        "ankle": landmark(0.840, 0.830, 0.05),
    }

    landmarks = {
        "nose": dict(left["nose"]),
        "primary.nose": dict(left["nose"]),
    }
    add_side(landmarks, "left", left)
    add_side(landmarks, "primary", left)
    duplicate_primary_to_side(landmarks, "right", left, x_offset=0.09, z_offset=0.12)
    add_foot(landmarks, "left", (0.795, 0.842, 0.05), (0.945, 0.848, 0.06), (0.840, 0.830, 0.05))
    add_foot(landmarks, "primary", (0.795, 0.842, 0.05), (0.945, 0.848, 0.06), (0.840, 0.830, 0.05))
    add_foot(landmarks, "right", (0.885, 0.842, 0.17), (0.995, 0.848, 0.18), (0.930, 0.830, 0.17))
    return landmarks


def lying_tricep_extension_landmarks(factor: float) -> dict[str, dict[str, float]]:
    shoulder = landmark(0.380, 0.550, 0.0)
    elbow = landmark(0.540, 0.380, 0.03)
    wrist = landmark(mix(0.700, 0.430, factor), mix(0.210, 0.310, factor), 0.08)
    primary = {
        "nose": landmark(0.300, 0.540, -0.03),
        "shoulder": shoulder,
        "elbow": elbow,
        "wrist": wrist,
        "hip": landmark(0.700, 0.600, 0.0),
        "knee": landmark(0.820, 0.640, 0.02),
        "ankle": landmark(0.920, 0.680, 0.05),
    }

    landmarks = {"nose": dict(primary["nose"])}
    add_side(landmarks, "primary", primary)
    duplicate_primary_to_side(landmarks, "left", primary, x_offset=0.0, z_offset=0.10)
    duplicate_primary_to_side(landmarks, "right", primary, x_offset=0.060, z_offset=-0.10)
    add_foot(landmarks, "primary", (0.875, 0.692, 0.05), (0.995, 0.698, 0.06), (0.920, 0.680, 0.05))
    add_foot(landmarks, "left", (0.875, 0.692, 0.15), (0.995, 0.698, 0.16), (0.920, 0.680, 0.15))
    add_foot(landmarks, "right", (0.935, 0.692, -0.05), (0.995, 0.698, -0.04), (0.980, 0.680, -0.05))
    return landmarks


def standing_cable_tricep_extension_landmarks(factor: float) -> dict[str, dict[str, float]]:
    shoulder = landmark(0.520, 0.320, 0.0)
    elbow = landmark(0.500, 0.480, 0.03)
    wrist = landmark(mix(0.590, 0.510, factor), mix(0.470, 0.720, factor), 0.08)
    primary = {
        "nose": landmark(0.525, 0.190, -0.03),
        "shoulder": shoulder,
        "elbow": elbow,
        "wrist": wrist,
        "hip": landmark(0.520, 0.545, 0.0),
        "knee": landmark(0.520, 0.710, 0.02),
        "ankle": landmark(0.520, 0.865, 0.05),
    }

    landmarks = {"nose": dict(primary["nose"])}
    add_side(landmarks, "primary", primary)
    duplicate_primary_to_side(landmarks, "left", primary, x_offset=0.0, z_offset=0.10)
    duplicate_primary_to_side(landmarks, "right", primary, x_offset=0.090, z_offset=-0.12)
    add_foot(landmarks, "primary", (0.475, 0.877, 0.05), (0.625, 0.883, 0.06), (0.520, 0.865, 0.05))
    add_foot(landmarks, "left", (0.475, 0.877, 0.15), (0.625, 0.883, 0.16), (0.520, 0.865, 0.15))
    add_foot(landmarks, "right", (0.565, 0.877, -0.07), (0.715, 0.883, -0.06), (0.610, 0.865, -0.07))
    return landmarks


def suspension_tricep_press_landmarks(factor: float) -> dict[str, dict[str, float]]:
    shoulder = landmark(0.420, 0.360, 0.0)
    elbow = landmark(0.510, 0.460, 0.03)
    wrist = landmark(mix(0.400, 0.620, factor), mix(0.490, 0.580, factor), 0.08)
    primary = {
        "nose": landmark(0.370, 0.250, -0.03),
        "shoulder": shoulder,
        "elbow": elbow,
        "wrist": wrist,
        "hip": landmark(0.620, 0.580, 0.0),
        "knee": landmark(0.730, 0.700, 0.02),
        "ankle": landmark(0.840, 0.820, 0.05),
    }

    landmarks = {"nose": dict(primary["nose"])}
    add_side(landmarks, "primary", primary)
    duplicate_primary_to_side(landmarks, "right", primary, x_offset=0.0, z_offset=0.10)
    duplicate_primary_to_side(landmarks, "left", primary, x_offset=-0.090, z_offset=-0.12)
    add_foot(landmarks, "primary", (0.795, 0.832, 0.05), (0.945, 0.838, 0.06), (0.840, 0.820, 0.05))
    add_foot(landmarks, "right", (0.795, 0.832, 0.15), (0.945, 0.838, 0.16), (0.840, 0.820, 0.15))
    add_foot(landmarks, "left", (0.705, 0.832, -0.07), (0.855, 0.838, -0.06), (0.750, 0.820, -0.07))
    return landmarks


def archetype_function(archetype: str) -> Callable[[float], dict[str, dict[str, float]]]:
    if archetype == "bilateral_squat":
        return squat_landmarks
    if archetype == "bodyweight_pike":
        return pike_landmarks
    if archetype == "chest_supported_row":
        return chest_supported_row_landmarks
    if archetype == "horizontal_press":
        return pushup_landmarks
    if archetype == "jumping_jack":
        return jumping_jack_landmarks
    if archetype == "lying_tricep_extension":
        return lying_tricep_extension_landmarks
    if archetype == "preacher_curl":
        return preacher_curl_landmarks
    if archetype == "standing_cable_tricep_extension":
        return standing_cable_tricep_extension_landmarks
    if archetype == "standing_hip_flexion":
        return standing_hip_flexion_landmarks
    if archetype == "standing_reverse_curl":
        return standing_reverse_curl_landmarks
    if archetype == "suspension_tricep_press":
        return suspension_tricep_press_landmarks
    if archetype == "static_hold":
        return plank_landmarks
    raise SystemExit(f"unsupported archetype: {archetype}")


def factors_for_archetype(archetype: str) -> list[float]:
    if archetype == "jumping_jack":
        raw = [0, 0, 0.25, 0.55, 0.85, 1, 1, 1, 0.85, 0.55, 0.25, 0, 0, 0]
        return [smoothstep(factor) for factor in raw]
    if archetype == "standing_hip_flexion":
        raw = [0, 0, 0, 0.20, 0.45, 0.70, 0.90, 1, 1, 1, 0.80, 0.55, 0.30, 0.10, 0, 0, 0]
        return [smoothstep(factor) for factor in raw]
    if archetype == "standing_reverse_curl":
        raw = [0, 0, 0, 0.20, 0.45, 0.70, 0.90, 1, 1, 1, 0.80, 0.55, 0.30, 0.10, 0, 0, 0]
        return [smoothstep(factor) for factor in raw]
    if archetype == "preacher_curl":
        raw = [0, 0, 0, 0.20, 0.45, 0.70, 0.90, 1, 1, 1, 0.80, 0.55, 0.30, 0.10, 0, 0, 0]
        return [smoothstep(factor) for factor in raw]
    if archetype == "chest_supported_row":
        raw = [0, 0, 0, 0.20, 0.45, 0.70, 0.90, 1, 1, 1, 0.80, 0.55, 0.30, 0.10, 0, 0, 0]
        return [smoothstep(factor) for factor in raw]
    if archetype == "lying_tricep_extension":
        raw = [0, 0, 0, 0.20, 0.45, 0.70, 0.90, 1, 1, 1, 0.80, 0.55, 0.30, 0.10, 0, 0, 0]
        return [smoothstep(factor) for factor in raw]
    if archetype == "standing_cable_tricep_extension":
        raw = [0, 0, 0, 0.20, 0.45, 0.70, 0.90, 1, 1, 1, 0.80, 0.55, 0.30, 0.10, 0, 0, 0]
        return [smoothstep(factor) for factor in raw]
    if archetype == "bodyweight_pike":
        raw = [0, 0, 0, 0.20, 0.45, 0.70, 0.90, 1, 1, 1, 0.80, 0.55, 0.30, 0.10, 0, 0, 0]
        return [smoothstep(factor) for factor in raw]
    if archetype == "suspension_tricep_press":
        raw = [0, 0, 0, 0.20, 0.45, 0.70, 0.90, 1, 1, 1, 0.80, 0.55, 0.30, 0.10, 0, 0, 0]
        return [smoothstep(factor) for factor in raw]
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
        elif archetype == "jumping_jack":
            key = "jack_spread"
            shoulder_width = distance(landmarks["left.shoulder"], landmarks["right.shoulder"])
            hip_width = distance(landmarks["left.hip"], landmarks["right.hip"])
            left_arm = distance(landmarks["left.wrist"], landmarks["left.hip"]) / max(shoulder_width, 1e-9)
            right_arm = distance(landmarks["right.wrist"], landmarks["right.hip"]) / max(shoulder_width, 1e-9)
            leg = distance(landmarks["left.ankle"], landmarks["right.ankle"]) / max(hip_width, 1e-9)
            values.append(((left_arm + right_arm) / 2) + leg)
        elif archetype == "standing_hip_flexion":
            key = "left_hip_flexion_angle"
            values.append(angle_degrees(landmarks["left.shoulder"], landmarks["left.hip"], landmarks["left.knee"]))
        elif archetype == "standing_reverse_curl":
            key = "primary_elbow_angle"
            values.append(angle_degrees(landmarks["primary.shoulder"], landmarks["primary.elbow"], landmarks["primary.wrist"]))
        elif archetype == "preacher_curl":
            key = "primary_elbow_angle"
            values.append(angle_degrees(landmarks["primary.shoulder"], landmarks["primary.elbow"], landmarks["primary.wrist"]))
        elif archetype == "chest_supported_row":
            key = "left_elbow_angle"
            values.append(angle_degrees(landmarks["left.shoulder"], landmarks["left.elbow"], landmarks["left.wrist"]))
        elif archetype == "lying_tricep_extension":
            key = "primary_elbow_angle"
            values.append(angle_degrees(landmarks["primary.shoulder"], landmarks["primary.elbow"], landmarks["primary.wrist"]))
        elif archetype == "standing_cable_tricep_extension":
            key = "primary_elbow_angle"
            values.append(angle_degrees(landmarks["primary.shoulder"], landmarks["primary.elbow"], landmarks["primary.wrist"]))
        elif archetype == "bodyweight_pike":
            key = "primary_pike_angle"
            values.append(angle_degrees(landmarks["primary.shoulder"], landmarks["primary.hip"], landmarks["primary.ankle"]))
        elif archetype == "suspension_tricep_press":
            key = "primary_elbow_angle"
            values.append(angle_degrees(landmarks["primary.shoulder"], landmarks["primary.elbow"], landmarks["primary.wrist"]))

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
        "output_trace": repo_relative(output),
        "interval_ms": interval_ms,
        "retarget": normalizer.get("retarget"),
        "required_contacts": profile.get("required_contacts", []),
        "required_output_landmarks": profile.get("required_output_landmarks", []),
        "summary": summarize(frames, profile["archetype"]),
        "candidate_status": "canonical_archetype_candidate",
        "replacement_plan": "Candidate artifact only; do not bundle as guide motion. Replace with accepted first-party or licensed workout reference footage before promotion.",
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
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=None,
        help="candidate output directory; default is dist/motion-reference/archetype_candidates/<exercise_id>",
    )
    parser.add_argument(
        "--allow-app-resource-output",
        action="store_true",
        help="permit explicit writes under Sources/CamiFitApp/Resources/MotionDemos for non-pending profiles",
    )
    parser.add_argument("--interval-ms", type=int, default=100)
    return parser.parse_args()


def is_fail_closed_profile(profile: dict[str, Any]) -> bool:
    capture = profile.get("capture", {})
    if not isinstance(capture, dict):
        capture = {}
    return (
        str(profile.get("viewer_status", "unknown")) == "pending_reference_capture"
        or str(capture.get("status", "unknown")) in PENDING_CAPTURE_STATUSES
        or bool(capture.get("rejection_reason"))
    )


def output_path_for_profile(profile: dict[str, Any], output_dir: Path, default_output: bool) -> Path:
    exercise_id = profile["exercise_id"]
    if default_output:
        return output_dir / exercise_id / f"{exercise_id}.jsonl"
    return output_dir / f"{exercise_id}.jsonl"


def validate_output_target(profile: dict[str, Any], output: Path, allow_app_resource_output: bool) -> None:
    repo_root = Path(__file__).resolve().parents[2]
    app_motion_demos = repo_root / "Sources/CamiFitApp/Resources/MotionDemos"
    if not is_relative_to(output, app_motion_demos):
        return

    exercise_id = profile["exercise_id"]
    if not allow_app_resource_output:
        raise SystemExit(
            f"{exercise_id}: refusing to write canonical archetype trace into app MotionDemos "
            "without --allow-app-resource-output; write candidates to dist/motion-reference instead"
        )
    if is_fail_closed_profile(profile):
        raise SystemExit(
            f"{exercise_id}: refusing to write pending/rejected canonical archetype trace into app MotionDemos; "
            "capture exact accepted reference footage before promotion"
        )


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[2]
    default_output = args.output_dir is None
    output_dir = args.output_dir or (repo_root / "dist/motion-reference/archetype_candidates")
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
        output = output_path_for_profile(profile, output_dir, default_output)
        validate_output_target(profile, output, args.allow_app_resource_output)
        write_trace(profile, output, args.interval_ms)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
