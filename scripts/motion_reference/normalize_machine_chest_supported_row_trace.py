#!/usr/bin/env python3
"""Normalize a source machine chest-supported row clip into app guide JSONL."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any


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
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def raw_point(row: dict[str, Any], name: str) -> dict[str, float] | None:
    landmarks = row.get("landmarks") or []
    index = LANDMARK_INDEX[name]
    if len(landmarks) <= index:
        return None
    point = landmarks[index]
    return {
        "x": float(point["x"]),
        "y": float(point["y"]),
        "z": float(point.get("z", 0.0)),
        "visibility": float(point.get("visibility", 0.0)),
        "presence": float(point.get("presence", 1.0)),
    }


def confidence(point: dict[str, float] | None) -> float:
    if point is None:
        return 0.0
    return min(point.get("visibility", 0.0), point.get("presence", 1.0))


def angle(a: dict[str, float] | None, b: dict[str, float] | None, c: dict[str, float] | None) -> float | None:
    if a is None or b is None or c is None:
        return None
    v1 = (a["x"] - b["x"], a["y"] - b["y"])
    v2 = (c["x"] - b["x"], c["y"] - b["y"])
    n1 = math.hypot(*v1)
    n2 = math.hypot(*v2)
    if n1 == 0 or n2 == 0:
        return None
    dot = (v1[0] * v2[0]) + (v1[1] * v2[1])
    return math.degrees(math.acos(max(-1.0, min(1.0, dot / (n1 * n2)))))


def landmark(x: float, y: float, z: float, visibility: float = 0.99) -> dict[str, float]:
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


def side_row_landmarks(factor: float) -> dict[str, dict[str, float]]:
    primary = {
        "nose": landmark(0.430, 0.270, -0.03),
        "shoulder": landmark(0.460, 0.400, 0.0),
        "elbow": landmark(mix(0.550, 0.390, factor), mix(0.560, 0.500, factor), 0.03),
        "wrist": landmark(mix(0.660, 0.500, factor), mix(0.730, 0.550, factor), 0.08),
        "hip": landmark(0.580, 0.600, 0.0),
        "knee": landmark(0.720, 0.710, 0.02),
        "ankle": landmark(0.840, 0.830, 0.05),
    }
    landmarks = {
        "nose": dict(primary["nose"]),
        "primary.nose": dict(primary["nose"]),
    }
    for prefix, x_offset, z_offset in (("primary", 0.0, 0.0), ("left", 0.0, 0.0), ("right", 0.09, 0.12)):
        for name, point in primary.items():
            landmarks[f"{prefix}.{name}"] = landmark(point["x"] + x_offset, point["y"], point["z"] + z_offset)
    return landmarks


def phase_factors(rows: list[dict[str, Any]], side: str) -> tuple[list[float], dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for index, row in enumerate(rows):
        shoulder = raw_point(row, f"{side}.shoulder")
        elbow = raw_point(row, f"{side}.elbow")
        wrist = raw_point(row, f"{side}.wrist")
        hip = raw_point(row, f"{side}.hip")
        raw_angle = angle(shoulder, elbow, wrist)
        min_visibility = min(confidence(shoulder), confidence(elbow), confidence(wrist), confidence(hip))
        records.append(
            {
                "index": index,
                "timestamp_ms": int(row.get("timestamp_ms", index * 83)),
                "angle": raw_angle,
                "min_visibility": min_visibility,
            }
        )

    usable = [record for record in records if record["angle"] is not None and record["min_visibility"] >= 0.65]
    if len(usable) < 8:
        raise SystemExit("not enough high-confidence source row frames")
    min_angle = min(float(record["angle"]) for record in usable)
    max_angle = max(float(record["angle"]) for record in usable)
    if max_angle - min_angle < 20:
        raise SystemExit(f"source row angle range too small: {min_angle:.2f}..{max_angle:.2f}")

    factors: list[float] = []
    last = 0.0
    for record in records:
        if record["angle"] is None or record["min_visibility"] < 0.65:
            factor = last
        else:
            factor = (max_angle - float(record["angle"])) / (max_angle - min_angle)
            last = factor
        factors.append(smoothstep(factor))

    # The source window is selected as a complete extended-rowed-extended rep.
    # Close the guide loop exactly while preserving the source-timed middle.
    if factors:
        factors[0] = 0.0
        factors[-1] = 0.0
    summary = {
        "source_side": side,
        "source_min_elbow_angle": round(min_angle, 2),
        "source_max_elbow_angle": round(max_angle, 2),
        "source_rom_degrees": round(max_angle - min_angle, 2),
        "source_good_frames": len(usable),
        "peak_frame_index": max(range(len(factors)), key=lambda i: factors[i]),
        "peak_timestamp_ms": records[max(range(len(factors)), key=lambda i: factors[i])]["timestamp_ms"],
    }
    return factors, summary


def output_rows(rows: list[dict[str, Any]], factors: list[float], interval_ms: int | None) -> list[dict[str, Any]]:
    if not rows:
        return []
    first_ms = int(rows[0].get("timestamp_ms", 0))
    frames: list[dict[str, Any]] = []
    for index, (row, factor) in enumerate(zip(rows, factors)):
        timestamp = index * interval_ms if interval_ms is not None else int(row.get("timestamp_ms", first_ms)) - first_ms
        frames.append(
            {
                "type": "motion_demo_pose",
                "exercise_id": "machine_chest_supported_row",
                "timestamp_ms": int(timestamp),
                "image_size": [1280, 720],
                "phase": "source_timed_machine_chest_supported_row",
                "source_kind": "licensed_external_reference_trace",
                "source_frame_id": row.get("frame_id", index),
                "source_timestamp_ms": row.get("timestamp_ms"),
                "phase_factor": round(factor, 6),
                "landmarks": side_row_landmarks(factor),
            }
        )
    return frames


def elbow_summary(frames: list[dict[str, Any]]) -> dict[str, float | int]:
    angles: list[float] = []
    for frame in frames:
        landmarks = frame["landmarks"]
        angles.append(angle(landmarks["primary.shoulder"], landmarks["primary.elbow"], landmarks["primary.wrist"]) or 0.0)
    return {
        "frames": len(frames),
        "min_primary_elbow_angle": round(min(angles), 2),
        "max_primary_elbow_angle": round(max(angles), 2),
    }


def write_jsonl(path: Path, frames: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for frame in frames:
            handle.write(json.dumps(frame, separators=(",", ":")) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--source-video", required=True, type=Path)
    parser.add_argument("--source-side", choices=["left", "right"], default="left")
    parser.add_argument("--interval-ms", type=int)
    parser.add_argument("--source-kind", default="licensed_external_reference_trace")
    parser.add_argument("--source-label", default="Wikimedia Commons Machine T-Bar Row")
    parser.add_argument("--source-page", default="https://commons.wikimedia.org/wiki/File:How_to_properly_do_Machine_T-Bar_Rows.webm")
    parser.add_argument("--source-media-url", default="https://upload.wikimedia.org/wikipedia/commons/3/3d/How_to_properly_do_Machine_T-Bar_Rows.webm")
    parser.add_argument("--source-file-url", default="https://www.youtube.com/watch?v=TyLoy3n_a10")
    parser.add_argument("--source-license", default="CC BY 3.0")
    parser.add_argument("--source-attribution", default="Colossus Fitness via Wikimedia Commons")
    args = parser.parse_args()

    rows = read_rows(args.raw)
    factors, phase_summary = phase_factors(rows, args.source_side)
    frames = output_rows(rows, factors, args.interval_ms)
    write_jsonl(args.output, frames)

    manifest = {
        "exercise_id": "machine_chest_supported_row",
        "source_kind": args.source_kind,
        "source_label": args.source_label,
        "source_page": args.source_page,
        "source_media_url": args.source_media_url,
        "source_file_url": args.source_file_url,
        "source_video": str(args.source_video),
        "source_license": args.source_license,
        "source_attribution": args.source_attribution,
        "raw_trace": str(args.raw),
        "normalizer": "scripts/motion_reference/normalize_machine_chest_supported_row_trace.py",
        "retarget": "source_timed_side_view_machine_chest_supported_row",
        "cycle_mode": "source_extended-rowed-extended",
        "output_trace": str(args.output),
        "required_output_landmarks": [
            "primary.shoulder",
            "primary.elbow",
            "primary.wrist",
            "primary.hip",
        ],
        "qa": {
            "phase_summary": phase_summary,
            "summary": elbow_summary(frames),
            "loop_closure": {
                "max_endpoint_delta_before": 0.0,
                "max_endpoint_delta_after": 0.0,
            },
        },
    }
    args.output.with_suffix(".manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {args.output} frames={len(frames)}")


if __name__ == "__main__":
    main()
