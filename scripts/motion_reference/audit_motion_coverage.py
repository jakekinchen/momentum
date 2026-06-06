#!/usr/bin/env python3
"""Audit packaged exercise presets against scalable motion reference profiles."""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass
class DemoAudit:
    path: Path
    frame_count: int
    missing_required: list[str]
    missing_contacts: list[str]
    max_contact_delta: float | None
    max_loop_delta: float | None
    malformed_lines: list[int]

    @property
    def ok(self) -> bool:
        return (
            self.frame_count > 0
            and not self.malformed_lines
            and not self.missing_required
            and not self.missing_contacts
            and (self.max_contact_delta is None or self.max_contact_delta <= 0.001)
            and (self.max_loop_delta is None or self.max_loop_delta <= 0.002)
        )


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def load_presets(path: Path) -> dict[str, dict[str, Any]]:
    presets: dict[str, dict[str, Any]] = {}
    for preset_path in sorted(path.glob("*.json")):
        payload = load_json(preset_path)
        exercise_id = payload.get("id")
        if not exercise_id:
            raise SystemExit(f"{preset_path}: missing id")
        presets[exercise_id] = payload
    return presets


def load_profiles(path: Path) -> dict[str, dict[str, Any]]:
    payload = load_json(path)
    profiles: dict[str, dict[str, Any]] = {}
    for profile in payload.get("profiles", []):
        exercise_id = profile.get("exercise_id")
        if not exercise_id:
            raise SystemExit(f"{path}: profile missing exercise_id")
        profiles[exercise_id] = profile
    return profiles


def load_manifest(path: Path) -> dict[str, Any] | None:
    manifest_path = path.with_suffix(".manifest.json")
    if not manifest_path.exists():
        return None
    return load_json(manifest_path)


def point_delta(a: dict[str, Any], b: dict[str, Any]) -> float:
    dx = float(a.get("x", 0)) - float(b.get("x", 0))
    dy = float(a.get("y", 0)) - float(b.get("y", 0))
    dz = float(a.get("z", 0)) - float(b.get("z", 0))
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))


def audit_demo(path: Path, profile: dict[str, Any]) -> DemoAudit:
    frames: list[dict[str, Any]] = []
    malformed: list[int] = []
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                malformed.append(line_number)
                continue
            if record.get("type") not in {"motion_demo_pose", "pose"}:
                malformed.append(line_number)
                continue
            landmarks = record.get("landmarks")
            if not isinstance(landmarks, dict):
                malformed.append(line_number)
                continue
            frames.append(record)

    all_landmarks: set[str] = set()
    for frame in frames:
        all_landmarks.update(frame.get("landmarks", {}).keys())

    required = list(profile.get("required_output_landmarks", []))
    contacts = list(profile.get("required_contacts", []))
    missing_required = [name for name in required if name not in all_landmarks]
    missing_contacts = [name for name in contacts if name not in all_landmarks]
    max_contact_delta: float | None = None
    max_loop_delta: float | None = None

    if frames and contacts and not missing_contacts:
        first_landmarks = frames[0]["landmarks"]
        deltas: list[float] = []
        for frame in frames[1:]:
            landmarks = frame["landmarks"]
            for name in contacts:
                deltas.append(point_delta(first_landmarks[name], landmarks[name]))
        max_contact_delta = max(deltas) if deltas else 0.0

    if len(frames) > 1 and required and not missing_required:
        first_landmarks = frames[0]["landmarks"]
        last_landmarks = frames[-1]["landmarks"]
        max_loop_delta = max(point_delta(first_landmarks[name], last_landmarks[name]) for name in required)

    return DemoAudit(
        path=path,
        frame_count=len(frames),
        missing_required=missing_required,
        missing_contacts=missing_contacts,
        max_contact_delta=max_contact_delta,
        max_loop_delta=max_loop_delta,
        malformed_lines=malformed,
    )


def status_requires_demo(status: str) -> bool:
    return status in {"bundled_reference_trace", "trainer_reference_trace", "bundled_canonical_trace"}


def format_delta(value: float | None) -> str:
    if value is None:
        return "n/a"
    return f"{value:.6f}"


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--presets",
        type=Path,
        default=repo_root / "Sources/CamiFitApp/Resources/Presets",
        help="directory of packaged exercise preset JSON files",
    )
    parser.add_argument(
        "--motion-demos",
        type=Path,
        default=repo_root / "Sources/CamiFitApp/Resources/MotionDemos",
        help="directory of packaged motion demo JSONL files",
    )
    parser.add_argument(
        "--profiles",
        type=Path,
        default=script_dir / "exercise_motion_profiles.json",
        help="motion profile registry",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="fail when shipped/bundled profile demos are missing or invalid",
    )
    parser.add_argument(
        "--require-all-demos",
        action="store_true",
        help="fail until every packaged preset has a valid demo trace",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    presets = load_presets(args.presets)
    profiles = load_profiles(args.profiles)
    failures: list[str] = []
    pending: list[str] = []

    for exercise_id in sorted(presets):
        profile = profiles.get(exercise_id)
        demo_path = args.motion_demos / f"{exercise_id}.jsonl"

        if profile is None:
            failures.append(f"{exercise_id}: no motion profile")
            print(f"motion-coverage exercise_id={exercise_id} profile=missing demo=unchecked")
            continue

        status = str(profile.get("viewer_status", "unknown"))
        requires_demo = status_requires_demo(status) or args.require_all_demos
        if not demo_path.exists():
            line = (
                f"motion-coverage exercise_id={exercise_id} profile={status} "
                f"demo=missing normalizer={profile.get('normalizer', {}).get('status', 'unknown')}"
            )
            print(line)
            if requires_demo:
                failures.append(f"{exercise_id}: expected demo trace at {demo_path}")
            else:
                pending.append(exercise_id)
            continue

        audit = audit_demo(demo_path, profile)
        manifest = load_manifest(demo_path)
        manifest_status = "present" if manifest is not None else "missing"
        manifest_errors: list[str] = []
        if manifest is not None:
            if manifest.get("exercise_id") != exercise_id:
                manifest_errors.append("exercise_id_mismatch")
            summary_frames = manifest.get("summary", {}).get("frames")
            try:
                manifest_frame_count = int(summary_frames) if summary_frames is not None else None
            except (TypeError, ValueError):
                manifest_frame_count = None
                manifest_errors.append(f"summary_frames_invalid={summary_frames}")
            if manifest_frame_count is not None and manifest_frame_count != audit.frame_count:
                manifest_errors.append(f"summary_frames={summary_frames}_actual={audit.frame_count}")
        print(
            f"motion-coverage exercise_id={exercise_id} profile={status} demo={'ok' if audit.ok else 'invalid'} "
            f"frames={audit.frame_count} manifest={manifest_status}{'+' + ','.join(manifest_errors) if manifest_errors else ''} "
            f"contact_delta={format_delta(audit.max_contact_delta)} "
            f"loop_delta={format_delta(audit.max_loop_delta)}"
        )

        if manifest is None and requires_demo:
            failures.append(f"{exercise_id}: missing manifest next to demo trace")
        if manifest_errors and requires_demo:
            failures.append(f"{exercise_id}: manifest errors {manifest_errors}")
        if not audit.ok and requires_demo:
            if audit.malformed_lines:
                failures.append(f"{exercise_id}: malformed demo lines {audit.malformed_lines[:8]}")
            if audit.missing_required:
                failures.append(f"{exercise_id}: missing required landmarks {audit.missing_required}")
            if audit.missing_contacts:
                failures.append(f"{exercise_id}: missing contact landmarks {audit.missing_contacts}")
            if audit.max_contact_delta is not None and audit.max_contact_delta > 0.001:
                failures.append(f"{exercise_id}: contact delta {audit.max_contact_delta:.6f} exceeds 0.001")
            if audit.max_loop_delta is not None and audit.max_loop_delta > 0.002:
                failures.append(f"{exercise_id}: loop delta {audit.max_loop_delta:.6f} exceeds 0.002")

    extra_profiles = sorted(set(profiles) - set(presets))
    for exercise_id in extra_profiles:
        print(f"motion-coverage exercise_id={exercise_id} preset=missing profile=extra")

    print(
        f"motion-coverage summary presets={len(presets)} profiles={len(profiles)} "
        f"pending_reference_captures={len(pending)} failures={len(failures)}"
    )

    if failures and (args.strict or args.require_all_demos):
        for failure in failures:
            print(f"motion-coverage failure={failure}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
