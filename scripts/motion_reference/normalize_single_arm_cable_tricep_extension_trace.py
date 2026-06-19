#!/usr/bin/env python3
"""Normalize a source cable triceps-extension clip into app guide JSONL.

The accepted wger clip is semantically exact and has clear pushdown timing, but
its tight crop makes full-body MediaPipe skeletons unreliable. This normalizer
uses the licensed clip for source timing and projects the selected visual cycle
onto the app's stable side-view single-arm cable rig.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
IMAGE_SIZE = [1280, 720]
LANDMARK_INDEX = {
    "left.shoulder": 11,
    "right.shoulder": 12,
    "left.elbow": 13,
    "right.elbow": 14,
    "left.wrist": 15,
    "right.wrist": 16,
    "left.hip": 23,
    "right.hip": 24,
}


def read_rows(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                rows.append(json.loads(line))
    if not rows:
        raise SystemExit(f"empty raw trace: {path}")
    return rows


def confidence(point: dict[str, float] | None) -> float:
    if point is None:
        return 0.0
    return min(point.get("visibility", 0.0), point.get("presence", 1.0))


def raw_point(row: dict[str, Any], name: str) -> dict[str, float] | None:
    index = LANDMARK_INDEX[name]
    landmarks = row.get("landmarks") or []
    if len(landmarks) <= index:
        return None
    point = landmarks[index]
    return {
        "x": float(point["x"]),
        "y": float(point["y"]),
        "z": float(point.get("z", 0.0)),
        "visibility": float(point.get("visibility", 0.0)),
        "presence": float(point.get("presence", point.get("visibility", 0.0))),
    }


def landmark(x: float, y: float, z: float, visibility: float = 1.0) -> dict[str, float]:
    return {
        "x": round(x, 6),
        "y": round(y, 6),
        "z": round(z, 6),
        "visibility": round(visibility, 6),
        "presence": 1.0,
    }


def mix(a: float, b: float, factor: float) -> float:
    return a + ((b - a) * factor)


def smoothstep(value: float) -> float:
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - (2.0 * value))


def angle_degrees(a: dict[str, float], b: dict[str, float], c: dict[str, float]) -> float:
    v1 = (a["x"] - b["x"], a["y"] - b["y"])
    v2 = (c["x"] - b["x"], c["y"] - b["y"])
    n1 = math.hypot(*v1)
    n2 = math.hypot(*v2)
    if n1 == 0 or n2 == 0:
        return 0.0
    dot = (v1[0] * v2[0]) + (v1[1] * v2[1])
    return math.degrees(math.acos(max(-1.0, min(1.0, dot / (n1 * n2)))))


def add_side(
    landmarks: dict[str, dict[str, float]],
    prefix: str,
    primary: dict[str, dict[str, float]],
    *,
    x_offset: float,
    z_offset: float,
) -> None:
    for joint, point in primary.items():
        landmarks[f"{prefix}.{joint}"] = landmark(point["x"] + x_offset, point["y"], point["z"] + z_offset)


def add_foot(
    landmarks: dict[str, dict[str, float]],
    prefix: str,
    heel: tuple[float, float, float],
    toe: tuple[float, float, float],
) -> None:
    landmarks[f"{prefix}.heel"] = landmark(*heel)
    landmarks[f"{prefix}.foot.index"] = landmark(*toe)


def cable_triceps_landmarks(factor: float) -> dict[str, dict[str, float]]:
    factor = smoothstep(factor)
    primary = {
        "nose": landmark(0.525, 0.190, -0.03),
        "shoulder": landmark(0.520, 0.320, 0.0),
        "elbow": landmark(0.500, 0.480, 0.03),
        "wrist": landmark(mix(0.590, 0.510, factor), mix(0.470, 0.720, factor), 0.08),
        "hip": landmark(0.520, 0.545, 0.0),
        "knee": landmark(0.520, 0.710, 0.02),
        "ankle": landmark(0.520, 0.865, 0.05),
    }
    landmarks = {
        "nose": dict(primary["nose"]),
        "primary.nose": dict(primary["nose"]),
    }
    add_side(landmarks, "primary", primary, x_offset=0.0, z_offset=0.0)
    add_side(landmarks, "left", primary, x_offset=0.0, z_offset=0.10)
    add_side(landmarks, "right", primary, x_offset=0.090, z_offset=-0.12)
    add_foot(landmarks, "primary", (0.475, 0.877, 0.05), (0.625, 0.883, 0.06))
    add_foot(landmarks, "left", (0.475, 0.877, 0.15), (0.625, 0.883, 0.16))
    add_foot(landmarks, "right", (0.565, 0.877, -0.07), (0.715, 0.883, -0.06))
    return landmarks


def selected_cycle_rows(rows: list[dict[str, Any]], start_ms: int, extend_ms: int, end_ms: int) -> list[dict[str, Any]]:
    if not (start_ms < extend_ms < end_ms):
        raise SystemExit("expected start_ms < extend_ms < end_ms")
    selected = [
        row for row in rows
        if start_ms <= int(row.get("timestamp_ms", 0)) <= end_ms
    ]
    if len(selected) < 12:
        raise SystemExit(f"selected source cycle has too few rows: {len(selected)}")
    return selected


def source_factor(timestamp_ms: int, start_ms: int, extend_ms: int, end_ms: int) -> float:
    if timestamp_ms <= extend_ms:
        return smoothstep((timestamp_ms - start_ms) / max(extend_ms - start_ms, 1))
    return smoothstep((end_ms - timestamp_ms) / max(end_ms - extend_ms, 1))


def source_visibility_summary(rows: list[dict[str, Any]], side: str) -> dict[str, Any]:
    values: list[float] = []
    for row in rows:
        shoulder = raw_point(row, f"{side}.shoulder")
        elbow = raw_point(row, f"{side}.elbow")
        wrist = raw_point(row, f"{side}.wrist")
        hip = raw_point(row, f"{side}.hip")
        values.append(min(confidence(shoulder), confidence(elbow), confidence(wrist), confidence(hip)))
    return {
        "source_side": side,
        "frames": len(rows),
        "min_chain_confidence": round(min(values), 4),
        "median_chain_confidence": round(sorted(values)[len(values) // 2], 4),
        "frames_at_or_above_0_65": sum(1 for value in values if value >= 0.65),
    }


def output_frames(
    rows: list[dict[str, Any]],
    *,
    start_ms: int,
    extend_ms: int,
    end_ms: int,
) -> list[dict[str, Any]]:
    frames: list[dict[str, Any]] = []
    for row in rows:
        source_timestamp = int(row.get("timestamp_ms", 0))
        factor = source_factor(source_timestamp, start_ms, extend_ms, end_ms)
        frames.append(
            {
                "type": "motion_demo_pose",
                "exercise_id": "single_arm_cable_tricep_extension",
                "timestamp_ms": source_timestamp - start_ms,
                "image_size": IMAGE_SIZE,
                "phase": "source_timed_single_arm_cable_tricep_extension",
                "source_kind": "licensed_external_reference_trace",
                "source_frame_id": row.get("frame_id", len(frames)),
                "source_timestamp_ms": source_timestamp,
                "phase_factor": round(factor, 6),
                "landmarks": cable_triceps_landmarks(factor),
            }
        )
    if frames:
        frames[0]["phase_factor"] = 0.0
        frames[0]["landmarks"] = cable_triceps_landmarks(0.0)
        frames[-1]["phase_factor"] = 0.0
        frames[-1]["landmarks"] = cable_triceps_landmarks(0.0)
    return frames


def endpoint_delta(frames: list[dict[str, Any]]) -> float:
    if len(frames) < 2:
        return 0.0
    first = frames[0]["landmarks"]
    last = frames[-1]["landmarks"]
    delta = 0.0
    for name in sorted(set(first).intersection(last)):
        for axis in ("x", "y", "z"):
            delta = max(delta, abs(float(first[name][axis]) - float(last[name][axis])))
    return delta


def frame_summary(frames: list[dict[str, Any]]) -> dict[str, Any]:
    angles: list[float] = []
    factors: list[float] = []
    for frame in frames:
        landmarks = frame["landmarks"]
        angles.append(angle_degrees(landmarks["primary.shoulder"], landmarks["primary.elbow"], landmarks["primary.wrist"]))
        factors.append(float(frame.get("phase_factor", 0.0)))
    return {
        "frames": len(frames),
        "duration_ms": frames[-1]["timestamp_ms"] if frames else 0,
        "min_primary_elbow_angle": round(min(angles), 2),
        "max_primary_elbow_angle": round(max(angles), 2),
        "max_phase_factor": round(max(factors), 4),
        "peak_timestamp_ms": frames[max(range(len(factors)), key=lambda index: factors[index])]["timestamp_ms"] if frames else 0,
    }


def repo_relative(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path)


def write_jsonl(path: Path, frames: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for frame in frames:
            handle.write(json.dumps(frame, separators=(",", ":")) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--source-video", type=Path, required=True)
    parser.add_argument("--cycle-start-ms", type=int, required=True)
    parser.add_argument("--cycle-extend-ms", type=int, required=True)
    parser.add_argument("--cycle-end-ms", type=int, required=True)
    parser.add_argument("--source-side", choices=["left", "right"], default="left")
    parser.add_argument("--source-label", default="wger exercise 803 video 59 One Arm Triceps Extensions on Cable")
    parser.add_argument("--source-page", default="https://wger.de/api/v2/exerciseinfo/803/")
    parser.add_argument("--source-media-url", default="https://wger.de/media/exercise-video/803/589d24e5-aaee-455d-93fd-f0f01da5d9c6.MOV")
    parser.add_argument("--source-license", default="CC-BY-SA 4")
    parser.add_argument("--source-attribution", default="Goulart / wger exercise 803 video 59")
    args = parser.parse_args()

    rows = read_rows(args.raw)
    selected = selected_cycle_rows(rows, args.cycle_start_ms, args.cycle_extend_ms, args.cycle_end_ms)
    frames = output_frames(
        selected,
        start_ms=args.cycle_start_ms,
        extend_ms=args.cycle_extend_ms,
        end_ms=args.cycle_end_ms,
    )
    write_jsonl(args.output, frames)

    manifest = {
        "exercise_id": "single_arm_cable_tricep_extension",
        "source_kind": "licensed_external_reference_trace",
        "source_label": args.source_label,
        "source_page": args.source_page,
        "source_media_url": args.source_media_url,
        "source_video": repo_relative(args.source_video),
        "source_license": args.source_license,
        "source_attribution": args.source_attribution,
        "raw_trace": repo_relative(args.raw),
        "normalizer": "scripts/motion_reference/normalize_single_arm_cable_tricep_extension_trace.py",
        "retarget": "source_timed_side_view_single_arm_cable_tricep_extension",
        "cycle_mode": "source_flexed-extended-flexed",
        "cycle": {
            "start_ms": args.cycle_start_ms,
            "extend_ms": args.cycle_extend_ms,
            "end_ms": args.cycle_end_ms,
        },
        "output_trace": repo_relative(args.output),
        "required_output_landmarks": [
            "primary.shoulder",
            "primary.elbow",
            "primary.wrist",
            "primary.hip",
            "left.shoulder",
            "left.elbow",
            "left.wrist",
            "left.hip",
        ],
        "qa": {
            "source_visibility": source_visibility_summary(selected, args.source_side),
            "summary": frame_summary(frames),
            "loop_closure": {
                "max_endpoint_delta_after": round(endpoint_delta(frames), 6),
            },
        },
    }
    args.output.with_suffix(".manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {args.output} frames={len(frames)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
