#!/usr/bin/env python3
"""Densify and smooth review-gallery-only motion demo traces.

This is a visual-review postprocess, not a promotion normalizer. It preserves
the packaged exercise metadata while adding in-between frames and softening
single-frame landmark jumps that make the web mannequin look glitchy.
"""

from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any


NUMERIC_LANDMARK_FIELDS = ("x", "y", "z", "visibility", "presence")


def load_frames(path: Path) -> list[dict[str, Any]]:
    frames: list[dict[str, Any]] = []
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            frame = json.loads(line)
            if not isinstance(frame, dict) or not isinstance(frame.get("landmarks"), dict):
                raise SystemExit(f"{path}:{line_number}: expected motion_demo_pose with landmarks")
            frames.append(frame)
    if not frames:
        raise SystemExit(f"empty trace: {path}")
    return frames


def write_frames(path: Path, frames: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for frame in frames:
            handle.write(json.dumps(frame, separators=(",", ":")) + "\n")


def mix(a: float, b: float, factor: float) -> float:
    return a + ((b - a) * factor)


def landmark_distance(first: dict[str, float], second: dict[str, float]) -> float:
    return math.sqrt(
        sum((float(first.get(axis, 0.0)) - float(second.get(axis, 0.0))) ** 2 for axis in ("x", "y", "z"))
    )


def angle_degrees(a: dict[str, float], b: dict[str, float], c: dict[str, float]) -> float:
    bax = a["x"] - b["x"]
    bay = a["y"] - b["y"]
    bcx = c["x"] - b["x"]
    bcy = c["y"] - b["y"]
    dot = (bax * bcx) + (bay * bcy)
    norm_a = max(math.hypot(bax, bay), 1e-9)
    norm_c = max(math.hypot(bcx, bcy), 1e-9)
    return math.degrees(math.acos(max(-1.0, min(1.0, dot / (norm_a * norm_c)))))


def max_landmark_step(frames: list[dict[str, Any]]) -> dict[str, Any]:
    worst = {"value": 0.0, "frame_index": None, "landmark": None}
    for index, (first, second) in enumerate(zip(frames, frames[1:])):
        names = set(first["landmarks"]).intersection(second["landmarks"])
        for name in names:
            step = landmark_distance(first["landmarks"][name], second["landmarks"][name])
            if step > worst["value"]:
                worst = {"value": round(step, 6), "frame_index": index, "landmark": name}
    return worst


def max_phase_step(frames: list[dict[str, Any]]) -> dict[str, Any]:
    factors = [frame.get("phase_factor") for frame in frames if isinstance(frame.get("phase_factor"), (int, float))]
    worst = {"value": 0.0, "frame_index": None}
    for index, (first, second) in enumerate(zip(factors, factors[1:])):
        step = abs(float(second) - float(first))
        if step > worst["value"]:
            worst = {"value": round(step, 6), "frame_index": index}
    return worst


def max_primary_elbow_step(frames: list[dict[str, Any]]) -> dict[str, Any]:
    angles: list[float] = []
    for frame in frames:
        landmarks = frame["landmarks"]
        names = ("primary.shoulder", "primary.elbow", "primary.wrist")
        if all(name in landmarks for name in names):
            angles.append(angle_degrees(landmarks[names[0]], landmarks[names[1]], landmarks[names[2]]))

    worst = {"value": 0.0, "frame_index": None}
    for index, (first, second) in enumerate(zip(angles, angles[1:])):
        step = abs(second - first)
        if step > worst["value"]:
            worst = {"value": round(step, 4), "frame_index": index}
    return worst


def trace_metrics(frames: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "frames": len(frames),
        "max_landmark_step": max_landmark_step(frames),
        "max_phase_step": max_phase_step(frames),
        "max_primary_elbow_angle_step": max_primary_elbow_step(frames),
    }


def loop_endpoint_delta(frames: list[dict[str, Any]]) -> float:
    if len(frames) < 2:
        return 0.0
    first = frames[0]["landmarks"]
    last = frames[-1]["landmarks"]
    names = set(first).intersection(last)
    return max((landmark_distance(first[name], last[name]) for name in names), default=0.0)


def interpolate_landmark(
    first: dict[str, Any],
    second: dict[str, Any],
    factor: float,
) -> dict[str, Any]:
    landmark = copy.deepcopy(first)
    for key in NUMERIC_LANDMARK_FIELDS:
        if isinstance(first.get(key), (int, float)) and isinstance(second.get(key), (int, float)):
            landmark[key] = mix(float(first[key]), float(second[key]), factor)
    return landmark


def interpolate_frame(first: dict[str, Any], second: dict[str, Any], factor: float) -> dict[str, Any]:
    frame = copy.deepcopy(first if factor < 0.5 else second)
    frame["landmarks"] = {
        name: interpolate_landmark(first["landmarks"][name], second["landmarks"][name], factor)
        for name in sorted(set(first["landmarks"]).intersection(second["landmarks"]))
    }
    for key in ("phase_factor", "source_timestamp_ms"):
        if isinstance(first.get(key), (int, float)) and isinstance(second.get(key), (int, float)):
            frame[key] = mix(float(first[key]), float(second[key]), factor)
    return frame


def retime_frames(frames: list[dict[str, Any]], start_ms: int, end_ms: int) -> None:
    denominator = max(len(frames) - 1, 1)
    for index, frame in enumerate(frames):
        frame["timestamp_ms"] = round(mix(start_ms, end_ms, index / denominator))


def upsample_frames(frames: list[dict[str, Any]], factor: int) -> list[dict[str, Any]]:
    if factor <= 1 or len(frames) < 2:
        return copy.deepcopy(frames)

    output: list[dict[str, Any]] = []
    for index in range(len(frames) - 1):
        for step in range(factor):
            output.append(interpolate_frame(frames[index], frames[index + 1], step / factor))
    output.append(copy.deepcopy(frames[-1]))
    retime_frames(output, int(frames[0].get("timestamp_ms", 0)), int(frames[-1].get("timestamp_ms", 0)))
    return output


def smooth_frames(
    frames: list[dict[str, Any]],
    *,
    window: int,
    excluded_landmarks: set[str],
    close_loop: bool,
) -> list[dict[str, Any]]:
    if window <= 1 or len(frames) < 3:
        return copy.deepcopy(frames)
    if window % 2 == 0:
        raise SystemExit("--smooth-window must be odd")

    unique_count = len(frames) - 1 if close_loop else len(frames)
    source = copy.deepcopy(frames[:unique_count])
    output = copy.deepcopy(frames[:unique_count])
    radius = window // 2

    for index, frame in enumerate(output):
        for name, landmark in frame["landmarks"].items():
            if name in excluded_landmarks:
                continue
            samples: list[dict[str, Any]] = []
            for offset in range(-radius, radius + 1):
                sample_index = index + offset
                if close_loop:
                    sample_index %= unique_count
                elif sample_index < 0 or sample_index >= unique_count:
                    continue
                sample = source[sample_index]["landmarks"].get(name)
                if isinstance(sample, dict):
                    samples.append(sample)
            if len(samples) < 2:
                continue
            for axis in ("x", "y", "z"):
                if axis in landmark:
                    landmark[axis] = sum(float(sample.get(axis, landmark[axis])) for sample in samples) / len(samples)

    if close_loop:
        last = copy.deepcopy(frames[-1])
        last["landmarks"] = copy.deepcopy(output[0]["landmarks"])
        if "phase_factor" in output[0]:
            last["phase_factor"] = output[0]["phase_factor"]
        output.append(last)

    retime_frames(output, int(frames[0].get("timestamp_ms", 0)), int(frames[-1].get("timestamp_ms", 0)))
    return output


def parse_landmarks(value: str) -> set[str]:
    return {item.strip() for item in value.split(",") if item.strip()}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--upsample-factor", type=int, default=1)
    parser.add_argument("--smooth-window", type=int, default=1)
    parser.add_argument("--exclude-landmarks", default="")
    parser.add_argument("--loop-threshold", type=float, default=1e-5)
    parser.add_argument("--summary-output", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    before = load_frames(args.input)
    close_loop = loop_endpoint_delta(before) <= args.loop_threshold
    after = upsample_frames(before, args.upsample_factor)
    after = smooth_frames(
        after,
        window=args.smooth_window,
        excluded_landmarks=parse_landmarks(args.exclude_landmarks),
        close_loop=close_loop,
    )
    summary = {
        "input": str(args.input),
        "output": str(args.output),
        "upsample_factor": args.upsample_factor,
        "smooth_window": args.smooth_window,
        "excluded_landmarks": sorted(parse_landmarks(args.exclude_landmarks)),
        "loop_endpoint_delta_before": round(loop_endpoint_delta(before), 6),
        "loop_closed": close_loop,
        "before": trace_metrics(before),
        "after": trace_metrics(after),
    }
    write_frames(args.output, after)
    if args.summary_output is not None:
        args.summary_output.parent.mkdir(parents=True, exist_ok=True)
        args.summary_output.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
