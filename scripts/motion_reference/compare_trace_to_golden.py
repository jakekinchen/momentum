#!/usr/bin/env python3
"""Compare a candidate motion trace against a protected golden trace."""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path
from typing import Any

DEFAULT_LANDMARKS = [
    "primary.shoulder",
    "primary.hip",
    "primary.knee",
    "primary.ankle",
    "primary.foot.index",
    "secondary.hip",
    "secondary.knee",
    "secondary.ankle",
    "secondary.foot.index",
]


def load_motion_records(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            record = json.loads(line)
            if "landmarks" not in record:
                raise SystemExit(f"{path}:{line_number}: missing landmarks")
            records.append(record)
    if not records:
        raise SystemExit(f"{path}: no motion records found")
    return records


def landmark(record: dict[str, Any], name: str) -> dict[str, float]:
    value = record.get("landmarks", {}).get(name)
    if value is None:
        raise KeyError(name)
    return {
        "x": float(value["x"]),
        "y": float(value["y"]),
        "z": float(value.get("z", 0.0)),
    }


def midpoint(first: dict[str, float], second: dict[str, float]) -> dict[str, float]:
    return {
        "x": (first["x"] + second["x"]) / 2.0,
        "y": (first["y"] + second["y"]) / 2.0,
        "z": (first["z"] + second["z"]) / 2.0,
    }


def distance_xy(first: dict[str, float], second: dict[str, float]) -> float:
    return math.hypot(first["x"] - second["x"], first["y"] - second["y"])


def frame_scale(record: dict[str, Any], names: list[str]) -> float:
    try:
        return max(
            distance_xy(landmark(record, "primary.hip"), landmark(record, "primary.ankle")),
            distance_xy(landmark(record, "secondary.hip"), landmark(record, "secondary.ankle")),
        )
    except KeyError:
        points = [landmark(record, name) for name in names if name in record.get("landmarks", {})]
        if len(points) < 2:
            return 1.0
        min_x = min(point["x"] for point in points)
        max_x = max(point["x"] for point in points)
        min_y = min(point["y"] for point in points)
        max_y = max(point["y"] for point in points)
        return math.hypot(max_x - min_x, max_y - min_y) or 1.0


def normalized_point(record: dict[str, Any], name: str, names: list[str]) -> tuple[float, float]:
    point = landmark(record, name)
    try:
        anchor = midpoint(landmark(record, "primary.hip"), landmark(record, "secondary.hip"))
    except KeyError:
        anchor = landmark(record, "primary.hip")
    scale = frame_scale(record, names) or 1.0
    return ((point["x"] - anchor["x"]) / scale, (point["y"] - anchor["y"]) / scale)


def sample_value(values: list[float], progress: float) -> float:
    if len(values) == 1:
        return values[0]
    exact = progress * (len(values) - 1)
    lower = int(math.floor(exact))
    upper = min(lower + 1, len(values) - 1)
    weight = exact - lower
    return values[lower] * (1.0 - weight) + values[upper] * weight


def resampled_points(
    records: list[dict[str, Any]],
    name: str,
    names: list[str],
    samples: int,
) -> list[tuple[float, float]]:
    points = [normalized_point(record, name, names) for record in records]
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    return [
        (
            sample_value(xs, index / (samples - 1)),
            sample_value(ys, index / (samples - 1)),
        )
        for index in range(samples)
    ]


def angle_degrees(
    first: dict[str, float],
    vertex: dict[str, float],
    third: dict[str, float],
) -> float:
    vector_a = (first["x"] - vertex["x"], first["y"] - vertex["y"])
    vector_b = (third["x"] - vertex["x"], third["y"] - vertex["y"])
    length_a = math.hypot(*vector_a)
    length_b = math.hypot(*vector_b)
    if length_a == 0.0 or length_b == 0.0:
        return 0.0
    cosine = (vector_a[0] * vector_b[0] + vector_a[1] * vector_b[1]) / (length_a * length_b)
    return math.degrees(math.acos(max(-1.0, min(1.0, cosine))))


def knee_angles(records: list[dict[str, Any]], side: str, samples: int) -> list[float]:
    raw = [
        angle_degrees(
            landmark(record, f"{side}.hip"),
            landmark(record, f"{side}.knee"),
            landmark(record, f"{side}.ankle"),
        )
        for record in records
    ]
    return [sample_value(raw, index / (samples - 1)) for index in range(samples)]


ANGLE_SIGNAL_PATTERN = re.compile(
    r"^angle\(\s*([\w.]+)\s*,\s*([\w.]+)\s*,\s*([\w.]+)\s*\)$"
)


def preset_angle_signals(preset_path: Path) -> dict[str, tuple[str, str, str]]:
    """Three-landmark angle signals declared by an exercise preset, by name."""
    preset = json.loads(preset_path.read_text(encoding="utf-8"))
    signals: dict[str, tuple[str, str, str]] = {}
    for name, expression in preset.get("signals", {}).items():
        match = ANGLE_SIGNAL_PATTERN.match(expression.strip())
        if match:
            signals[name] = (match.group(1), match.group(2), match.group(3))
    return signals


def signal_angles(
    records: list[dict[str, Any]],
    points: tuple[str, str, str],
    samples: int,
) -> list[float] | None:
    try:
        raw = [
            angle_degrees(
                landmark(record, points[0]),
                landmark(record, points[1]),
                landmark(record, points[2]),
            )
            for record in records
        ]
    except KeyError:
        return None
    return [sample_value(raw, index / (samples - 1)) for index in range(samples)]


def compare_angle_series(golden: list[float], candidate: list[float]) -> dict[str, Any]:
    delta = [abs(a - b) for a, b in zip(golden, candidate)]
    return {
        "golden_min": min(golden),
        "golden_max": max(golden),
        "candidate_min": min(candidate),
        "candidate_max": max(candidate),
        "mean_abs_delta_degrees": mean(delta),
        "max_abs_delta_degrees": max(delta),
        "correlation": pearson(golden, candidate),
    }


def pearson(first: list[float], second: list[float]) -> float | None:
    if len(first) != len(second) or len(first) < 2:
        return None
    mean_a = sum(first) / len(first)
    mean_b = sum(second) / len(second)
    centered_a = [value - mean_a for value in first]
    centered_b = [value - mean_b for value in second]
    denom_a = math.sqrt(sum(value * value for value in centered_a))
    denom_b = math.sqrt(sum(value * value for value in centered_b))
    if denom_a == 0.0 or denom_b == 0.0:
        return None
    return sum(a * b for a, b in zip(centered_a, centered_b)) / (denom_a * denom_b)


def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def compare(args: argparse.Namespace) -> dict[str, Any]:
    golden_records = load_motion_records(args.golden)
    candidate_records = load_motion_records(args.candidate)
    landmarks = args.landmark or DEFAULT_LANDMARKS
    samples = args.samples
    if samples < 2:
        raise SystemExit("--samples must be at least 2")

    per_landmark: dict[str, dict[str, float]] = {}
    all_errors: list[float] = []
    missing: list[str] = []

    for name in landmarks:
        try:
            golden_points = resampled_points(golden_records, name, landmarks, samples)
            candidate_points = resampled_points(candidate_records, name, landmarks, samples)
        except KeyError:
            missing.append(name)
            continue
        errors = [
            math.hypot(golden[0] - candidate[0], golden[1] - candidate[1])
            for golden, candidate in zip(golden_points, candidate_points)
        ]
        all_errors.extend(errors)
        per_landmark[name] = {
            "mean_xy_error_body_scaled": mean(errors),
            "max_xy_error_body_scaled": max(errors),
        }

    primary_golden = knee_angles(golden_records, "primary", samples)
    primary_candidate = knee_angles(candidate_records, "primary", samples)
    secondary_golden = knee_angles(golden_records, "secondary", samples)
    secondary_candidate = knee_angles(candidate_records, "secondary", samples)

    primary_delta = [abs(a - b) for a, b in zip(primary_golden, primary_candidate)]
    secondary_delta = [abs(a - b) for a, b in zip(secondary_golden, secondary_candidate)]

    preset_signals: dict[str, Any] = {}
    skipped_signals: list[str] = []
    if args.preset is not None:
        for name, points in sorted(preset_angle_signals(args.preset).items()):
            golden_series = signal_angles(golden_records, points, samples)
            candidate_series = signal_angles(candidate_records, points, samples)
            if golden_series is None or candidate_series is None:
                skipped_signals.append(name)
                continue
            preset_signals[name] = compare_angle_series(golden_series, candidate_series)

    result = {
        "golden": str(args.golden),
        "candidate": str(args.candidate),
        "normalization": "hip-midpoint anchored, leg-length body-scaled xy",
        "samples": samples,
        "golden_record_count": len(golden_records),
        "candidate_record_count": len(candidate_records),
        "landmarks": landmarks,
        "missing_landmarks": missing,
        "mean_xy_error_body_scaled": mean(all_errors),
        "max_xy_error_body_scaled": max(all_errors) if all_errors else 0.0,
        "per_landmark": per_landmark,
        "primary_knee_angle": {
            "golden_min": min(primary_golden),
            "golden_max": max(primary_golden),
            "candidate_min": min(primary_candidate),
            "candidate_max": max(primary_candidate),
            "mean_abs_delta_degrees": mean(primary_delta),
            "max_abs_delta_degrees": max(primary_delta),
            "correlation": pearson(primary_golden, primary_candidate),
        },
        "secondary_knee_angle": {
            "golden_min": min(secondary_golden),
            "golden_max": max(secondary_golden),
            "candidate_min": min(secondary_candidate),
            "candidate_max": max(secondary_candidate),
            "mean_abs_delta_degrees": mean(secondary_delta),
            "max_abs_delta_degrees": max(secondary_delta),
            "correlation": pearson(secondary_golden, secondary_candidate),
        },
    }
    if args.preset is not None:
        result["preset"] = str(args.preset)
        result["preset_angle_signals"] = preset_signals
        result["preset_angle_signals_skipped"] = skipped_signals
    failures = []
    if args.max_preset_signal_mean_abs_delta is not None:
        for name, stats in preset_signals.items():
            if stats["mean_abs_delta_degrees"] > args.max_preset_signal_mean_abs_delta:
                failures.append(f"preset_angle_signals.{name}.mean_abs_delta_degrees")
    if args.min_preset_signal_correlation is not None:
        for name, stats in preset_signals.items():
            correlation = stats["correlation"]
            if correlation is None or correlation < args.min_preset_signal_correlation:
                failures.append(f"preset_angle_signals.{name}.correlation")
    if args.max_mean_xy_error is not None and result["mean_xy_error_body_scaled"] > args.max_mean_xy_error:
        failures.append("mean_xy_error_body_scaled")
    if (
        args.max_primary_knee_mean_abs_delta is not None
        and result["primary_knee_angle"]["mean_abs_delta_degrees"]
        > args.max_primary_knee_mean_abs_delta
    ):
        failures.append("primary_knee_angle.mean_abs_delta_degrees")
    correlation = result["primary_knee_angle"]["correlation"]
    if (
        args.min_primary_knee_correlation is not None
        and (correlation is None or correlation < args.min_primary_knee_correlation)
    ):
        failures.append("primary_knee_angle.correlation")
    result["threshold_failures"] = failures
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--golden", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--samples", type=int, default=64)
    parser.add_argument("--landmark", action="append", help="Landmark to compare; repeatable.")
    parser.add_argument(
        "--preset",
        type=Path,
        help="Exercise preset JSON; compares every three-landmark angle() signal it declares instead of relying on the built-in knee angles only.",
    )
    parser.add_argument("--max-preset-signal-mean-abs-delta", type=float)
    parser.add_argument("--min-preset-signal-correlation", type=float)
    parser.add_argument("--max-mean-xy-error", type=float)
    parser.add_argument("--max-primary-knee-mean-abs-delta", type=float)
    parser.add_argument("--min-primary-knee-correlation", type=float)
    args = parser.parse_args()

    result = compare(args)
    text = json.dumps(result, indent=2, sort_keys=True)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text + "\n", encoding="utf-8")
    print(
        "trace_compare "
        f"mean_xy={result['mean_xy_error_body_scaled']:.4f} "
        f"primary_knee_delta={result['primary_knee_angle']['mean_abs_delta_degrees']:.2f} "
        f"primary_knee_corr={result['primary_knee_angle']['correlation']}"
    )
    if result["threshold_failures"]:
        print("threshold_failures=" + ",".join(result["threshold_failures"]))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
