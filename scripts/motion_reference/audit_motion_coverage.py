#!/usr/bin/env python3
"""Audit packaged exercise presets against scalable motion reference profiles."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

MAX_FORCED_LOOP_DELTA = 0.08
LICENSED_EXTERNAL_CAPTURE_STATUSES = {
    "licensed_external_reference_clip",
    "licensed_external_workout_clip",
}
SUPPORTED_REJECTED_SOURCE_REVIEW_STATUSES = {
    "none_retained_for_promotion_review",
    "none_rejected_after_review",
}
PENDING_SOURCE_SEARCH_REVIEW_STATUSES = SUPPORTED_REJECTED_SOURCE_REVIEW_STATUSES | {
    "source_search_pending_fail_closed",
}
PROTECTED_GOLDEN_TRACE_SHA256 = {
    "bodyweight_lunge": "04920c88fe91d6bd1c0c218bc8ae04477006bc97a6a1111e458d134f9f3a8a65",
}
MEDIAPIPE_LANDMARK_NAMES = [
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


@dataclass
class DemoAudit:
    path: Path
    frame_count: int
    frames: list[dict[str, Any]]
    missing_required: list[str]
    missing_contacts: list[str]
    max_contact_delta: float | None
    max_loop_delta: float | None
    malformed_lines: list[int]
    timestamp_errors: list[int]
    non_finite_values: list[str]
    out_of_bounds_landmarks: list[str]

    @property
    def ok(self) -> bool:
        return (
            self.frame_count > 0
            and not self.malformed_lines
            and not self.timestamp_errors
            and not self.non_finite_values
            and not self.out_of_bounds_landmarks
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


def parse_swift_string_set(source: str, set_name: str) -> set[str]:
    pattern = re.compile(rf"\b{re.escape(set_name)}\b[^\n=]*=\s*\[")
    match = pattern.search(source)
    if match is None:
        raise ValueError(f"missing Swift string set {set_name}")
    end = source.find("]", match.end())
    if end < 0:
        raise ValueError(f"unterminated Swift string set {set_name}")
    body = source[match.end():end]
    return {
        json.loads(f'"{value}"')
        for value in re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', body)
    }


def load_swift_string_set(path: Path, set_name: str) -> set[str]:
    return parse_swift_string_set(path.read_text(encoding="utf-8"), set_name)


def point_delta(a: dict[str, Any], b: dict[str, Any]) -> float:
    dx = float(a.get("x", 0)) - float(b.get("x", 0))
    dy = float(a.get("y", 0)) - float(b.get("y", 0))
    dz = float(a.get("z", 0)) - float(b.get("z", 0))
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))


def finite_float(value: Any) -> float | None:
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(parsed):
        return None
    return parsed


def append_limited(items: list[str], value: str, limit: int = 16) -> None:
    if len(items) < limit:
        items.append(value)


def append_failure_once(failures: list[str], value: str) -> None:
    if value not in failures:
        failures.append(value)


def audit_demo(path: Path, profile: dict[str, Any]) -> DemoAudit:
    frames: list[dict[str, Any]] = []
    malformed: list[int] = []
    timestamp_errors: list[int] = []
    previous_timestamp: float | None = None
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
            timestamp = finite_float(record.get("timestamp_ms"))
            if timestamp is None or (previous_timestamp is not None and timestamp <= previous_timestamp):
                timestamp_errors.append(line_number)
            else:
                previous_timestamp = timestamp
            frames.append(record)

    all_landmarks: set[str] = set()
    non_finite_values: list[str] = []
    out_of_bounds_landmarks: list[str] = []
    for frame_index, frame in enumerate(frames):
        landmarks = frame.get("landmarks", {})
        all_landmarks.update(landmarks.keys())
        for name, point in landmarks.items():
            if not isinstance(point, dict):
                append_limited(non_finite_values, f"{name}:not_object")
                continue
            x = finite_float(point.get("x"))
            y = finite_float(point.get("y"))
            z = finite_float(point.get("z"))
            if x is None or y is None or z is None:
                append_limited(non_finite_values, f"{name}:non_finite")
                continue
            if x < 0.0 or x > 1.0 or y < 0.0 or y > 1.0:
                append_limited(out_of_bounds_landmarks, f"frame={frame_index}:{name}:x={x:.3f}:y={y:.3f}")

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
        frames=frames,
        missing_required=missing_required,
        missing_contacts=missing_contacts,
        max_contact_delta=max_contact_delta,
        max_loop_delta=max_loop_delta,
        malformed_lines=malformed,
        timestamp_errors=timestamp_errors,
        non_finite_values=non_finite_values,
        out_of_bounds_landmarks=out_of_bounds_landmarks,
    )


@dataclass
class QualityAudit:
    failures: list[str]
    metrics: dict[str, float]

    @property
    def ok(self) -> bool:
        return not self.failures


def status_requires_demo(status: str) -> bool:
    return status in {"bundled_reference_trace", "trainer_reference_trace", "bundled_canonical_trace"}


def status_forbids_playable_demo(status: str) -> bool:
    return status in {"pending_reference_capture"}


def capture_status(profile: dict[str, Any]) -> str:
    capture = profile.get("capture", {})
    if not isinstance(capture, dict):
        return "unknown"
    return str(capture.get("status", "unknown"))


def is_pending_reference_capture(profile: dict[str, Any]) -> bool:
    return str(profile.get("viewer_status", "")) == "pending_reference_capture" or capture_status(profile).startswith("pending_")


def validation_role(profile: dict[str, Any]) -> str:
    return str(profile.get("validation_role", ""))


def has_accepted_reference_clip(profile: dict[str, Any]) -> bool:
    if validation_role(profile) == "protected_golden_comparator":
        return capture_status(profile) == "protected_golden_reference"
    return capture_status(profile) in {
        "first_party_webcam_reference",
        "first_party_trainer_reference_video",
        "first_party_authored_keyposes",
        "licensed_external_reference_clip",
        "licensed_external_workout_clip",
    }


def has_first_party_capture(profile: dict[str, Any]) -> bool:
    return capture_status(profile) in {
        "first_party_webcam_reference",
        "first_party_trainer_reference_video",
    }


def reference_acceptance_failures(profile: dict[str, Any], *, include_pending: bool = False) -> list[str]:
    capture = profile.get("capture", {})
    if not isinstance(capture, dict):
        capture = {}
    promotable = has_accepted_reference_clip(profile)
    if include_pending and capture_status(profile) in {"pending_first_party_capture", "pending_licensed_reference_clip"}:
        promotable = True
    if not promotable:
        return []

    failures: list[str] = []
    if capture.get("rejection_reason"):
        failures.append("rejected_reference_capture")
    normalizer = profile.get("normalizer", {})
    normalizer_status = ""
    if isinstance(normalizer, dict):
        normalizer_status = str(normalizer.get("status", ""))
    if normalizer_status.startswith("rejected"):
        failures.append(f"rejected_normalizer_status:{normalizer_status}")
    return failures


def non_empty_string(value: Any) -> str | None:
    if isinstance(value, str) and value.strip():
        return value
    return None


def manifest_or_capture_value(manifest: dict[str, Any], capture: dict[str, Any], key: str) -> str | None:
    return non_empty_string(manifest.get(key)) or non_empty_string(capture.get(key))


def manifest_path_value(manifest: dict[str, Any], key: str) -> str | None:
    return non_empty_string(manifest.get(key))


def integer_value(value: Any) -> int | None:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return None
    return parsed


def require_artifact_integrity(
    failures: list[str],
    manifest: dict[str, Any],
    label: str,
    path: Path,
) -> None:
    integrity = manifest.get("artifact_integrity")
    if not isinstance(integrity, dict):
        append_failure_once(failures, "missing_reference_metadata:artifact_integrity")
        return

    record = integrity.get(label)
    if not isinstance(record, dict):
        failures.append(f"missing_reference_metadata:artifact_integrity.{label}")
        return

    expected_bytes = integer_value(record.get("bytes"))
    expected_sha256 = non_empty_string(record.get("sha256"))
    if expected_bytes is None:
        failures.append(f"missing_reference_metadata:artifact_integrity.{label}.bytes")
    if expected_sha256 is None:
        failures.append(f"missing_reference_metadata:artifact_integrity.{label}.sha256")
    if expected_bytes is None or expected_sha256 is None or not path.exists():
        return

    actual_bytes = path.stat().st_size
    if actual_bytes != expected_bytes:
        failures.append(
            f"artifact_bytes_mismatch:{label}=expected_{expected_bytes}_actual_{actual_bytes}"
        )
    actual_sha256 = sha256_hex(path)
    if actual_sha256 != expected_sha256:
        failures.append(f"artifact_sha256_mismatch:{label}")


def require_manifest_fields(
    failures: list[str],
    manifest: dict[str, Any],
    capture: dict[str, Any],
    fields: list[str],
) -> None:
    for field in fields:
        if not manifest_or_capture_value(manifest, capture, field):
            failures.append(f"missing_reference_metadata:{field}")


def require_manifest_paths(
    failures: list[str],
    manifest: dict[str, Any],
    fields: list[str],
) -> None:
    for field in fields:
        value = manifest_path_value(manifest, field)
        if value is None:
            failures.append(f"missing_reference_path:{field}")
            continue
        path = repo_relative_path(value)
        if path is None or not path.exists():
            failures.append(f"missing_reference_artifact:{field}={value}")
            continue
        require_artifact_integrity(failures, manifest, field, path)


def declared_artifact_paths(manifest: dict[str, Any]) -> list[tuple[str, str]]:
    artifacts: list[tuple[str, str]] = []
    for field in ["source_video", "raw_trace", "normalizer", "output_trace", "golden_trace", "candidate_trace"]:
        value = manifest_path_value(manifest, field)
        if value is not None:
            artifacts.append((field, value))

    comparison = manifest.get("golden_comparison")
    if isinstance(comparison, dict):
        for field in ["golden_trace", "candidate_trace", "comparison_report"]:
            value = manifest_path_value(comparison, field)
            if value is not None:
                artifacts.append((f"golden_comparison.{field}", value))
    return artifacts


def require_declared_artifact_integrity(
    failures: list[str],
    manifest: dict[str, Any],
) -> None:
    for label, value in declared_artifact_paths(manifest):
        path = repo_relative_path(value)
        if path is None or not path.exists():
            append_failure_once(failures, f"missing_reference_artifact:{label}={value}")
            continue
        require_artifact_integrity(failures, manifest, label, path)


def require_protected_golden_trace_hash(
    failures: list[str],
    profile: dict[str, Any],
    manifest: dict[str, Any],
) -> None:
    if validation_role(profile) != "protected_golden_comparator":
        return

    exercise_id = non_empty_string(profile.get("exercise_id")) or non_empty_string(manifest.get("exercise_id"))
    if exercise_id is None:
        failures.append("missing_reference_metadata:protected_golden.exercise_id")
        return

    expected_sha256 = PROTECTED_GOLDEN_TRACE_SHA256.get(exercise_id)
    if expected_sha256 is None:
        failures.append(f"missing_reference_metadata:protected_golden_sha256:{exercise_id}")
        return

    golden_trace = manifest_path_value(manifest, "golden_trace")
    if golden_trace is None:
        failures.append("missing_reference_path:protected_golden.golden_trace")
        return

    path = repo_relative_path(golden_trace)
    if path is None or not path.exists():
        failures.append(f"missing_reference_artifact:protected_golden.golden_trace={golden_trace}")
        return

    actual_sha256 = sha256_hex(path)
    if actual_sha256 != expected_sha256:
        failures.append(f"protected_golden_sha256_mismatch:{exercise_id}")

    comparison = manifest.get("golden_comparison")
    if isinstance(comparison, dict):
        comparison_golden_trace = manifest_path_value(comparison, "golden_trace")
        if comparison_golden_trace != golden_trace:
            failures.append("protected_golden_comparison_golden_trace_mismatch")


def require_playable_acceptance_status(
    failures: list[str],
    manifest: dict[str, Any],
) -> None:
    if manifest.get("playable_trace_packaged") is not True:
        failures.append("playable_trace_not_explicitly_packaged")
    status = str(manifest.get("acceptance_status", "")).strip().lower()
    if not status:
        failures.append("missing_reference_metadata:acceptance_status")
    elif not (
        status.startswith("accepted")
        or status.startswith("protected_golden")
    ):
        failures.append(f"unaccepted_reference_status:{status}")


def require_resolved_license_review(
    failures: list[str],
    manifest: dict[str, Any],
    capture: dict[str, Any],
) -> None:
    license_text = manifest_or_capture_value(manifest, capture, "source_license")
    if not license_text:
        return
    lowered = license_text.lower()
    if "pending" not in lowered and "review needed" not in lowered and "review still" not in lowered:
        return
    if str(manifest.get("license_review_status", "")).lower() == "accepted":
        return
    failures.append("unresolved_source_license_review")


def rejected_candidate_source_present(candidate: dict[str, Any]) -> bool:
    return any(
        non_empty_string(candidate.get(key))
        for key in ["source_page", "source_media_url", "source_url", "source_video"]
    )


def rejected_candidate_failures(candidate: Any, index: int) -> list[str]:
    if not isinstance(candidate, dict):
        return [f"rejected_candidates[{index}]:not_object"]

    failures: list[str] = []
    if not rejected_candidate_source_present(candidate):
        failures.append(f"rejected_candidates[{index}]:missing_source")
    for field in ["source_license", "source_attribution", "decision", "reason"]:
        if not non_empty_string(candidate.get(field)):
            failures.append(f"rejected_candidates[{index}]:missing_{field}")

    decision = non_empty_string(candidate.get("decision"))
    if decision is not None and "rejected" not in decision.lower():
        failures.append(f"rejected_candidates[{index}]:decision_not_rejected")
    return failures


def rejected_source_candidates(profile: dict[str, Any], manifest: dict[str, Any], capture: dict[str, Any]) -> list[Any]:
    candidates: list[Any] = []
    for source in [capture, manifest, profile]:
        source_candidates = source.get("rejected_candidates")
        if isinstance(source_candidates, list):
            candidates.extend(source_candidates)
    return candidates


def rejected_source_review_record(profile: dict[str, Any], manifest: dict[str, Any], capture: dict[str, Any]) -> dict[str, Any] | None:
    for source in [capture, manifest, profile]:
        review = source.get("rejected_sources")
        if isinstance(review, dict):
            return review
    return None


def require_rejected_source_review(
    failures: list[str],
    profile: dict[str, Any],
    manifest: dict[str, Any],
    capture: dict[str, Any],
) -> None:
    candidates = rejected_source_candidates(profile, manifest, capture)
    if candidates:
        for index, candidate in enumerate(candidates):
            for failure in rejected_candidate_failures(candidate, index):
                failures.append(f"missing_reference_metadata:{failure}")
        return

    review = rejected_source_review_record(profile, manifest, capture)
    if not isinstance(review, dict):
        failures.append("missing_reference_metadata:rejected_sources_or_rejected_candidates")
        return

    status = non_empty_string(review.get("status"))
    if status is None:
        failures.append("missing_reference_metadata:rejected_sources.status")
    elif status not in SUPPORTED_REJECTED_SOURCE_REVIEW_STATUSES:
        failures.append(f"unsupported_rejected_sources_status:{status}")

    if not non_empty_string(review.get("review_scope")):
        failures.append("missing_reference_metadata:rejected_sources.review_scope")
    if not non_empty_string(review.get("reason")):
        failures.append("missing_reference_metadata:rejected_sources.reason")


def pending_source_search_failures(
    profile: dict[str, Any],
    manifest: dict[str, Any] | None = None,
) -> list[str]:
    if not is_pending_reference_capture(profile):
        return []

    capture = profile.get("capture", {})
    if not isinstance(capture, dict):
        capture = {}
    manifest = manifest or {}

    failures: list[str] = []
    candidates = rejected_source_candidates(profile, manifest, capture)
    if candidates:
        for index, candidate in enumerate(candidates):
            for failure in rejected_candidate_failures(candidate, index):
                failures.append(f"pending_source_search:{failure}")
        return failures

    review = rejected_source_review_record(profile, manifest, capture)
    if not isinstance(review, dict):
        return ["pending_source_search:rejected_sources_or_rejected_candidates"]

    status = non_empty_string(review.get("status"))
    if status is None:
        failures.append("pending_source_search:rejected_sources.status")
    elif status not in PENDING_SOURCE_SEARCH_REVIEW_STATUSES:
        failures.append(f"pending_source_search:unsupported_rejected_sources_status:{status}")

    if not non_empty_string(review.get("review_scope")):
        failures.append("pending_source_search:rejected_sources.review_scope")
    if not non_empty_string(review.get("reason")):
        failures.append("pending_source_search:rejected_sources.reason")
    return failures


def declared_qa_gates(profile: dict[str, Any], manifest: dict[str, Any]) -> set[str]:
    gates: set[str] = set()
    for source in (profile.get("qa_gates"), manifest.get("qa_gates")):
        if isinstance(source, list):
            gates.update(str(item) for item in source if isinstance(item, str))
    return gates


def require_any_qa_gate(failures: list[str], gates: set[str], label: str, accepted: set[str]) -> None:
    if gates.isdisjoint(accepted):
        failures.append(f"missing_reference_qa_gate:{label}")


def require_golden_comparison_decision(
    failures: list[str],
    manifest: dict[str, Any],
) -> None:
    comparison = manifest.get("golden_comparison")
    if not isinstance(comparison, dict):
        failures.append("missing_reference_metadata:golden_comparison")
        return

    status = non_empty_string(comparison.get("status"))
    if status is None:
        failures.append("missing_reference_metadata:golden_comparison.status")
        return

    normalized = status.lower()
    if normalized == "not_applicable":
        if not non_empty_string(comparison.get("reason")):
            failures.append("missing_reference_metadata:golden_comparison.reason")
        return

    if normalized in {"passed", "reviewed"}:
        for field in ["golden_trace", "candidate_trace", "comparison_report"]:
            value = manifest_path_value(comparison, field)
            if value is None:
                failures.append(f"missing_reference_path:golden_comparison.{field}")
                continue
            path = repo_relative_path(value)
            if path is None or not path.exists():
                failures.append(f"missing_reference_artifact:golden_comparison.{field}={value}")
                continue
            require_artifact_integrity(
                failures,
                manifest,
                f"golden_comparison.{field}",
                path,
            )
        return

    if normalized == "failed":
        failures.append("golden_comparison_failed")
        return

    failures.append(f"unsupported_golden_comparison_status:{status}")


def require_review_and_replay_evidence(
    failures: list[str],
    manifest: dict[str, Any],
    exercise_id: str,
) -> None:
    visual_review = manifest.get("visual_review")
    if not isinstance(visual_review, dict):
        failures.append("missing_reference_metadata:visual_review")
    else:
        status = str(visual_review.get("status", "")).strip().lower()
        if status not in {"passed", "reviewed"}:
            failures.append(f"visual_review_status_not_passed:{status or 'missing'}")
        if not non_empty_string(visual_review.get("evidence")):
            failures.append("missing_reference_metadata:visual_review.evidence")

    engine_replay = manifest.get("engine_replay")
    if not isinstance(engine_replay, dict):
        failures.append("missing_reference_metadata:engine_replay")
    else:
        status = str(engine_replay.get("status", "")).strip().lower()
        if status != "passed":
            failures.append(f"engine_replay_status_not_passed:{status or 'missing'}")
        if not non_empty_string(engine_replay.get("test")):
            failures.append("missing_reference_metadata:engine_replay.test")

        has_rep_count = finite_float(engine_replay.get("actual_final_reps")) is not None
        hold_value = engine_replay.get("actual_hold_target_reached")
        has_hold_result = isinstance(hold_value, bool)
        if not has_rep_count and not has_hold_result:
            failures.append("missing_reference_metadata:engine_replay.result")

    live_app_review = manifest.get("live_app_review")
    if not isinstance(live_app_review, dict):
        failures.append("missing_reference_metadata:live_app_review")
        return

    status = str(live_app_review.get("status", "")).strip().lower()
    if status != "passed":
        failures.append(f"live_app_review_status_not_passed:{status or 'missing'}")
    if not non_empty_string(live_app_review.get("evidence")):
        failures.append("missing_reference_metadata:live_app_review.evidence")
    if not non_empty_string(live_app_review.get("app_bundle")):
        failures.append("missing_reference_metadata:live_app_review.app_bundle")
    installed_jsonls = live_app_review.get("installed_playable_jsonls")
    if not isinstance(installed_jsonls, int) or installed_jsonls <= 0:
        failures.append("missing_reference_metadata:live_app_review.installed_playable_jsonls")
    installed_ids = live_app_review.get("installed_playable_trace_ids")
    if not isinstance(installed_ids, list) or not installed_ids:
        failures.append("missing_reference_metadata:live_app_review.installed_playable_trace_ids")
    else:
        normalized_ids = [str(item).strip() for item in installed_ids if isinstance(item, str) and item.strip()]
        if len(normalized_ids) != len(installed_ids):
            failures.append("malformed_reference_metadata:live_app_review.installed_playable_trace_ids")
        elif installed_jsonls is not None and installed_jsonls != len(normalized_ids):
            failures.append("live_app_review_installed_count_mismatch")
        if exercise_id not in normalized_ids:
            failures.append(f"live_app_review_missing_exercise:{exercise_id}")


def manifest_reference_acceptance_failures(
    profile: dict[str, Any],
    manifest: dict[str, Any] | None,
) -> list[str]:
    if not has_accepted_reference_clip(profile):
        return []
    if manifest is None:
        return ["missing_reference_manifest"]

    capture = profile.get("capture", {})
    if not isinstance(capture, dict):
        capture = {}

    failures: list[str] = []
    source_kind = str(manifest.get("source_kind", ""))
    capture_status_value = capture_status(profile)
    qa_gates = declared_qa_gates(profile, manifest)
    require_playable_acceptance_status(failures, manifest)
    require_resolved_license_review(failures, manifest, capture)
    require_protected_golden_trace_hash(failures, profile, manifest)
    require_any_qa_gate(
        failures,
        qa_gates,
        "viewer_review",
        {"viewer_reviewed", "agent_visual_reviewed"},
    )
    require_any_qa_gate(
        failures,
        qa_gates,
        "engine_replay",
        {"engine_counts_one_rep", "engine_accepts_hold"},
    )
    require_golden_comparison_decision(failures, manifest)
    exercise_id = str(profile.get("exercise_id") or manifest.get("exercise_id") or "").strip()
    if not exercise_id:
        failures.append("missing_reference_metadata:exercise_id")
    require_review_and_replay_evidence(failures, manifest, exercise_id)

    if validation_role(profile) == "protected_golden_comparator":
        if source_kind not in {"trainer_reference_video", "trainer_reference_trace", "protected_golden_reference"}:
            failures.append(f"unexpected_reference_source_kind:{source_kind}")
        require_manifest_fields(
            failures,
            manifest,
            capture,
            [
                "source_label",
                "source_media_url",
                "source_license",
                "source_attribution",
            ],
        )
        if not (
            manifest_or_capture_value(manifest, capture, "source_page")
            or manifest_or_capture_value(manifest, capture, "source_url")
        ):
            failures.append("missing_reference_metadata:source_page_or_source_url")
        require_manifest_paths(
            failures,
            manifest,
            ["raw_trace", "source_video", "normalizer", "output_trace", "golden_trace", "candidate_trace"],
        )
        return failures

    if capture_status_value in {"first_party_webcam_reference", "first_party_trainer_reference_video"}:
        if source_kind not in {"trainer_reference_trace", "first_party_reference_trace"}:
            failures.append(f"unexpected_reference_source_kind:{source_kind}")
        require_manifest_fields(
            failures,
            manifest,
            capture,
            ["source_label", "source_license", "source_attribution"],
        )
        require_manifest_paths(
            failures,
            manifest,
            ["raw_trace", "source_video", "normalizer", "output_trace"],
        )
        return failures

    if capture_status_value == "first_party_authored_keyposes":
        if source_kind != "canonical_archetype_authored":
            failures.append(f"unexpected_reference_source_kind:{source_kind}")
        require_manifest_fields(
            failures,
            manifest,
            capture,
            ["source_label", "source_license", "source_attribution"],
        )
        require_manifest_paths(
            failures,
            manifest,
            ["normalizer", "output_trace"],
        )
        return failures

    if capture_status_value in LICENSED_EXTERNAL_CAPTURE_STATUSES:
        if source_kind != "licensed_external_reference_trace":
            failures.append(f"unexpected_reference_source_kind:{source_kind}")
        require_any_qa_gate(
            failures,
            qa_gates,
            "source_pose_review",
            {"raw_pose_reviewed", "source_clip_reviewed"},
        )
        require_rejected_source_review(failures, profile, manifest, capture)
        require_manifest_fields(
            failures,
            manifest,
            capture,
            [
                "source_label",
                "source_page",
                "source_media_url",
                "source_license",
                "source_attribution",
            ],
        )
        require_manifest_paths(
            failures,
            manifest,
            ["raw_trace", "source_video", "normalizer", "output_trace"],
        )
        return failures

    return failures


REVIEW_ONLY_PACKAGING_SCOPE = "motion_review_gallery_demo_only"


def is_review_only_manifest(manifest: dict[str, Any]) -> bool:
    scope = str(manifest.get("packaging_scope") or "").strip().lower()
    if scope != REVIEW_ONLY_PACKAGING_SCOPE:
        return False
    acceptance = str(manifest.get("acceptance_status") or "").strip().lower()
    if acceptance.startswith(("accepted", "protected_golden")):
        return False
    return acceptance.startswith(("blocked", "pending", "rejected"))


def promoted_manifest(manifest: dict[str, Any]) -> bool:
    if is_review_only_manifest(manifest):
        return False
    status = str(manifest.get("acceptance_status", "")).strip().lower()
    return (
        manifest.get("playable_trace_packaged") is True
        or status.startswith("accepted")
        or status.startswith("protected_golden")
    )


def motion_demo_inventory_failures(
    motion_demos: Path,
    presets: dict[str, dict[str, Any]],
    profiles: dict[str, dict[str, Any]],
) -> list[str]:
    failures: list[str] = []
    for demo_path in sorted(motion_demos.glob("*.jsonl")):
        exercise_id = demo_path.stem
        manifest = load_manifest(demo_path)
        review_only = manifest is not None and is_review_only_manifest(manifest)
        if exercise_id not in presets and not review_only:
            failures.append(f"{exercise_id}: playable demo trace has no packaged preset")
        if exercise_id not in profiles:
            failures.append(f"{exercise_id}: playable demo trace has no motion profile")

    for manifest_path in sorted(motion_demos.glob("*.manifest.json")):
        exercise_id = manifest_path.name.removesuffix(".manifest.json")
        manifest = load_json(manifest_path)
        if manifest.get("exercise_id") and manifest.get("exercise_id") != exercise_id:
            failures.append(f"{exercise_id}: manifest exercise_id mismatch {manifest.get('exercise_id')}")
        if is_review_only_manifest(manifest):
            # Review-only gallery demos ship real bytes, so their integrity
            # records stay enforced even though they are not promotable.
            if not (motion_demos / f"{exercise_id}.jsonl").exists():
                failures.append(f"{exercise_id}: review-only manifest has no playable demo trace")
            manifest_failures = []
            require_declared_artifact_integrity(manifest_failures, manifest)
            for failure in manifest_failures:
                failures.append(f"{exercise_id}: {failure}")
            continue
        if not promoted_manifest(manifest):
            continue
        if exercise_id not in presets:
            failures.append(f"{exercise_id}: promoted manifest has no packaged preset")
        if exercise_id not in profiles:
            failures.append(f"{exercise_id}: promoted manifest has no motion profile")
        if not (motion_demos / f"{exercise_id}.jsonl").exists():
            failures.append(f"{exercise_id}: promoted manifest has no playable demo trace")
        manifest_failures = []
        require_declared_artifact_integrity(manifest_failures, manifest)
        for failure in manifest_failures:
            failures.append(f"{exercise_id}: {failure}")
    return failures


def strict_fail_closed_inventory_failures(
    motion_demos: Path,
    presets: dict[str, dict[str, Any]],
    profiles: dict[str, dict[str, Any]],
) -> list[str]:
    failures = motion_demo_inventory_failures(motion_demos, presets, profiles)

    extra_profiles = sorted(set(profiles) - set(presets))
    for exercise_id in extra_profiles:
        profile = profiles[exercise_id]
        manifest = load_manifest(motion_demos / f"{exercise_id}.jsonl")
        for failure in pending_source_search_failures(profile, manifest):
            failures.append(f"{exercise_id}: {failure}")

    for exercise_id, profile in sorted(profiles.items()):
        status = str(profile.get("viewer_status", "unknown"))
        if not status_forbids_playable_demo(status):
            continue
        demo_path = motion_demos / f"{exercise_id}.jsonl"
        if demo_path.exists():
            manifest = load_manifest(demo_path)
            if manifest is not None and is_review_only_manifest(manifest):
                continue
            failures.append(
                f"{exercise_id}: pending reference capture must not ship playable demo trace at {demo_path}"
            )
    return failures


def guide_ready_inventory_failures(
    motion_demos: Path,
    presets: dict[str, dict[str, Any]],
    profiles: dict[str, dict[str, Any]],
    guide_ready_ids: set[str],
    reference_capture_ids: set[str],
) -> list[str]:
    failures: list[str] = []
    playable_ids = {path.stem for path in motion_demos.glob("*.jsonl")}
    review_only_ids = {
        exercise_id
        for exercise_id in playable_ids
        if (manifest := load_manifest(motion_demos / f"{exercise_id}.jsonl")) is not None
        and is_review_only_manifest(manifest)
    }
    guide_playable_ids = playable_ids - review_only_ids

    for exercise_id in sorted(guide_playable_ids - guide_ready_ids):
        failures.append(f"{exercise_id}: playable JSONL is not listed as guide-ready")
    for exercise_id in sorted(guide_ready_ids - guide_playable_ids):
        failures.append(f"{exercise_id}: guide-ready preset missing playable JSONL")
    for exercise_id in sorted(guide_ready_ids & review_only_ids):
        failures.append(f"{exercise_id}: guide-ready preset must not ship a review-only manifest")
    for exercise_id in sorted(guide_ready_ids & reference_capture_ids):
        failures.append(f"{exercise_id}: preset cannot be both guide-ready and reference-capture-required")
    for exercise_id in sorted((reference_capture_ids & playable_ids) - review_only_ids):
        failures.append(f"{exercise_id}: reference-capture preset must not ship playable JSONL")

    pending_profile_ids = {
        exercise_id
        for exercise_id, profile in profiles.items()
        if is_pending_reference_capture(profile)
    }
    for exercise_id in sorted(pending_profile_ids - reference_capture_ids):
        failures.append(f"{exercise_id}: pending profile is not listed as reference-capture-required")
    for exercise_id in sorted(reference_capture_ids - pending_profile_ids):
        failures.append(f"{exercise_id}: reference-capture ID has no pending motion profile")

    for exercise_id in sorted(guide_ready_ids):
        profile = profiles.get(exercise_id)
        manifest = load_manifest(motion_demos / f"{exercise_id}.jsonl")

        if exercise_id not in presets:
            failures.append(f"{exercise_id}: guide-ready preset missing packaged preset JSON")
        if profile is None:
            failures.append(f"{exercise_id}: guide-ready preset missing motion profile")
        else:
            status = str(profile.get("viewer_status", "unknown"))
            capture = capture_status(profile)
            if not status_requires_demo(status):
                failures.append(f"{exercise_id}: guide-ready preset has non-demo viewer_status {status}")
            if not has_accepted_reference_clip(profile):
                failures.append(f"{exercise_id}: guide-ready preset has unaccepted capture status {capture}")

        if manifest is None:
            failures.append(f"{exercise_id}: guide-ready preset missing manifest")
            continue
        if manifest.get("exercise_id") != exercise_id:
            failures.append(f"{exercise_id}: guide-ready manifest exercise_id mismatch {manifest.get('exercise_id')}")
        if manifest.get("playable_trace_packaged") is not True:
            failures.append(f"{exercise_id}: guide-ready manifest playable_trace_packaged is not true")
        live_app_review = manifest.get("live_app_review")
        if isinstance(live_app_review, dict):
            # Review-only gallery demos are excluded: live_app_review counts
            # guide-playable traces, not review-scoped ones.
            installed_jsonls = live_app_review.get("installed_playable_jsonls")
            if installed_jsonls != len(guide_playable_ids):
                failures.append(
                    f"{exercise_id}: guide-ready live_app_review installed_playable_jsonls={installed_jsonls} "
                    f"does not match packaged playable inventory {len(guide_playable_ids)}"
                )
            installed_ids = live_app_review.get("installed_playable_trace_ids")
            if isinstance(installed_ids, list):
                normalized_installed_ids = {
                    str(item).strip()
                    for item in installed_ids
                    if isinstance(item, str) and str(item).strip()
                }
                if normalized_installed_ids != guide_playable_ids:
                    failures.append(
                        f"{exercise_id}: guide-ready live_app_review installed_playable_trace_ids "
                        "do not match packaged playable inventory"
                    )
        if profile is not None:
            for failure in manifest_reference_acceptance_failures(profile, manifest):
                failures.append(f"{exercise_id}: guide-ready manifest {failure}")
    return failures


def quality_gate_enforced(profile: dict[str, Any], *, include_pending: bool = False) -> bool:
    gates = profile.get("quality_gates")
    if not isinstance(gates, dict):
        return False
    when = str(gates.get("enforce_when", "accepted_reference_clip"))
    if when == "always":
        return True
    if has_accepted_reference_clip(profile):
        return True
    return include_pending and capture_status(profile) in {
        "pending_first_party_capture",
        "pending_licensed_reference_clip",
    }


def nested_value(payload: dict[str, Any], path: str) -> Any:
    value: Any = payload
    for part in path.split("."):
        if not isinstance(value, dict) or part not in value:
            return None
        value = value[part]
    return value


def point_xy_delta(a: dict[str, Any], b: dict[str, Any]) -> float:
    dx = float(a.get("x", 0)) - float(b.get("x", 0))
    dy = float(a.get("y", 0)) - float(b.get("y", 0))
    return math.sqrt((dx * dx) + (dy * dy))


def angle_degrees(a: dict[str, Any], b: dict[str, Any], c: dict[str, Any]) -> float | None:
    v1 = (float(a.get("x", 0)) - float(b.get("x", 0)), float(a.get("y", 0)) - float(b.get("y", 0)))
    v2 = (float(c.get("x", 0)) - float(b.get("x", 0)), float(c.get("y", 0)) - float(b.get("y", 0)))
    dot = (v1[0] * v2[0]) + (v1[1] * v2[1])
    n1 = math.sqrt((v1[0] * v1[0]) + (v1[1] * v1[1]))
    n2 = math.sqrt((v2[0] * v2[0]) + (v2[1] * v2[1]))
    if n1 == 0 or n2 == 0:
        return None
    return math.degrees(math.acos(max(-1.0, min(1.0, dot / (n1 * n2)))))


def engine_landmark_name(media_pipe_name: str) -> str:
    return media_pipe_name.replace("_", ".")


def named_mediapipe_landmarks(record: dict[str, Any]) -> dict[str, dict[str, Any]] | None:
    landmarks = record.get("landmarks")
    if not isinstance(landmarks, list) or len(landmarks) != len(MEDIAPIPE_LANDMARK_NAMES):
        return None
    return {
        engine_landmark_name(name): landmark
        for name, landmark in zip(MEDIAPIPE_LANDMARK_NAMES, landmarks)
        if isinstance(landmark, dict)
    }


def load_raw_source_frame(path: Path, source_frame_id: int) -> dict[str, Any] | None:
    if not path.exists():
        return None
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            if int(record.get("frame_id", -1)) == source_frame_id:
                return record
    return None


def repo_relative_path(value: Any) -> Path | None:
    if not isinstance(value, str) or not value:
        return None
    path = Path(value)
    if path.is_absolute():
        return path
    return Path(__file__).resolve().parents[2] / path


def sha256_hex(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def shoulder_width(landmarks: dict[str, Any]) -> float | None:
    left = landmarks.get("left.shoulder")
    right = landmarks.get("right.shoulder")
    if not isinstance(left, dict) or not isinstance(right, dict):
        return None
    return abs(float(left.get("x", 0)) - float(right.get("x", 0)))


def wrist_spread_ratio(landmarks: dict[str, Any]) -> float | None:
    width = shoulder_width(landmarks)
    left = landmarks.get("left.wrist")
    right = landmarks.get("right.wrist")
    if width is None or width <= 0 or not isinstance(left, dict) or not isinstance(right, dict):
        return None
    return abs(float(left.get("x", 0)) - float(right.get("x", 0))) / width


def elbow_angle(landmarks: dict[str, Any], side: str) -> float | None:
    shoulder = landmarks.get(f"{side}.shoulder")
    elbow = landmarks.get(f"{side}.elbow")
    wrist = landmarks.get(f"{side}.wrist")
    if not isinstance(shoulder, dict) or not isinstance(elbow, dict) or not isinstance(wrist, dict):
        return None
    return angle_degrees(shoulder, elbow, wrist)


def select_demo_source_frame(frames: list[dict[str, Any]], source_frame_id: int) -> dict[str, Any] | None:
    candidates = [frame for frame in frames if int(frame.get("source_frame_id", -1)) == source_frame_id]
    if not candidates:
        return None

    def wrist_height(frame: dict[str, Any]) -> float:
        landmarks = frame.get("landmarks", {})
        wrists = [
            landmarks.get("left.wrist", {}).get("y"),
            landmarks.get("right.wrist", {}).get("y"),
        ]
        values = [float(value) for value in wrists if value is not None]
        return sum(values) / len(values) if values else float("inf")

    return min(candidates, key=wrist_height)


def audit_quality_gates(
    profile: dict[str, Any],
    demo: DemoAudit,
    manifest: dict[str, Any] | None,
) -> QualityAudit:
    gates = profile.get("quality_gates")
    if not isinstance(gates, dict):
        return QualityAudit(failures=[], metrics={})

    failures: list[str] = []
    metrics: dict[str, float] = {}
    summary = manifest.get("summary", {}) if isinstance(manifest, dict) else {}

    max_summary_values = gates.get("max_manifest_summary_values", {})
    if isinstance(max_summary_values, dict):
        for path, limit in sorted(max_summary_values.items()):
            threshold = finite_float(limit)
            value = finite_float(nested_value(summary, str(path)))
            if threshold is None:
                failures.append(f"quality_gate_config_invalid:{path}")
                continue
            if value is None:
                failures.append(f"quality_metric_missing:{path}")
                continue
            metrics[f"summary.{path}"] = value
            if value > threshold:
                failures.append(f"{path}={value:.4f}_exceeds_{threshold:.4f}")

    min_summary_values = gates.get("min_manifest_summary_values", {})
    if isinstance(min_summary_values, dict):
        for path, limit in sorted(min_summary_values.items()):
            threshold = finite_float(limit)
            value = finite_float(nested_value(summary, str(path)))
            if threshold is None:
                failures.append(f"quality_gate_config_invalid:{path}")
                continue
            if value is None:
                failures.append(f"quality_metric_missing:{path}")
                continue
            metrics[f"summary.{path}"] = value
            if value < threshold:
                failures.append(f"{path}={value:.4f}_below_{threshold:.4f}")

    smoothness = gates.get("motion_smoothness", {})
    if isinstance(smoothness, dict):
        landmarks = [str(item) for item in smoothness.get("landmarks", [])]
        max_adjacent_threshold = finite_float(smoothness.get("max_adjacent_delta"))
        max_second_threshold = finite_float(smoothness.get("max_second_difference"))
        max_adjacent = 0.0
        max_second = 0.0
        for name in landmarks:
            points: list[dict[str, Any]] = []
            missing = False
            for frame in demo.frames:
                landmark = frame.get("landmarks", {}).get(name)
                if not isinstance(landmark, dict):
                    missing = True
                    break
                points.append(landmark)
            if missing:
                failures.append(f"quality_landmark_missing:{name}")
                continue
            for first, second in zip(points, points[1:]):
                max_adjacent = max(max_adjacent, point_xy_delta(first, second))
            for previous, current, following in zip(points, points[1:], points[2:]):
                second_delta = math.sqrt(
                    (
                        float(following.get("x", 0))
                        - (2 * float(current.get("x", 0)))
                        + float(previous.get("x", 0))
                    )
                    ** 2
                    + (
                        float(following.get("y", 0))
                        - (2 * float(current.get("y", 0)))
                        + float(previous.get("y", 0))
                    )
                    ** 2
                )
                max_second = max(max_second, second_delta)
        if landmarks:
            metrics["motion.max_adjacent_delta"] = max_adjacent
            metrics["motion.max_second_difference"] = max_second
        if max_adjacent_threshold is not None and max_adjacent > max_adjacent_threshold:
            failures.append(
                f"motion.max_adjacent_delta={max_adjacent:.4f}_exceeds_{max_adjacent_threshold:.4f}"
            )
        if max_second_threshold is not None and max_second > max_second_threshold:
            failures.append(
                f"motion.max_second_difference={max_second:.4f}_exceeds_{max_second_threshold:.4f}"
            )

    min_y_ranges = gates.get("min_landmark_y_ranges", [])
    if isinstance(min_y_ranges, list):
        for item in min_y_ranges:
            if not isinstance(item, dict):
                failures.append("quality_gate_config_invalid:min_landmark_y_ranges")
                continue
            landmarks = [str(name) for name in item.get("landmarks", [])]
            threshold = finite_float(item.get("min_y_range"))
            label = str(item.get("label", "landmark_y_range"))
            if threshold is None:
                failures.append(f"quality_gate_config_invalid:{label}")
                continue
            for name in landmarks:
                values: list[float] = []
                for frame in demo.frames:
                    landmark = frame.get("landmarks", {}).get(name)
                    if not isinstance(landmark, dict):
                        failures.append(f"quality_landmark_missing:{name}")
                        values = []
                        break
                    y = finite_float(landmark.get("y"))
                    if y is None:
                        failures.append(f"quality_landmark_non_finite:{name}.y")
                        values = []
                        break
                    values.append(y)
                if not values:
                    continue
                y_range = max(values) - min(values)
                metrics[f"{label}.{name}"] = y_range
                if y_range < threshold:
                    failures.append(f"{label}.{name}={y_range:.4f}_below_{threshold:.4f}")

    source_shape = gates.get("source_shape_residual", {})
    if isinstance(source_shape, dict) and source_shape:
        raw_trace = repo_relative_path(source_shape.get("raw_trace"))
        source_frame_id_value = source_shape.get("source_frame_id")
        try:
            source_frame_id = int(source_frame_id_value)
        except (TypeError, ValueError):
            source_frame_id = -1
        raw_record = load_raw_source_frame(raw_trace, source_frame_id) if raw_trace is not None else None
        demo_frame = select_demo_source_frame(demo.frames, source_frame_id)
        if raw_trace is None:
            failures.append("source_shape.raw_trace_missing_config")
        elif raw_record is None:
            failures.append(f"source_shape.raw_frame_missing:{source_frame_id}")
        elif demo_frame is None:
            failures.append(f"source_shape.demo_frame_missing:{source_frame_id}")
        else:
            source_landmarks = named_mediapipe_landmarks(raw_record)
            demo_landmarks = demo_frame.get("landmarks", {})
            if source_landmarks is None or not isinstance(demo_landmarks, dict):
                failures.append("source_shape.landmarks_invalid")
            else:
                wrist_delta_limit = finite_float(source_shape.get("max_wrist_spread_ratio_delta"))
                source_wrist_spread = wrist_spread_ratio(source_landmarks)
                demo_wrist_spread = wrist_spread_ratio(demo_landmarks)
                if source_wrist_spread is None or demo_wrist_spread is None:
                    failures.append("source_shape.wrist_spread_missing")
                else:
                    wrist_delta = abs(demo_wrist_spread - source_wrist_spread)
                    metrics["source_shape.wrist_spread_ratio_delta"] = wrist_delta
                    if wrist_delta_limit is not None and wrist_delta > wrist_delta_limit:
                        failures.append(
                            f"source_shape.wrist_spread_delta={wrist_delta:.4f}_exceeds_{wrist_delta_limit:.4f}"
                        )

                elbow_delta_limit = finite_float(source_shape.get("max_elbow_angle_delta_degrees"))
                for side in ("left", "right"):
                    source_angle = elbow_angle(source_landmarks, side)
                    demo_angle = elbow_angle(demo_landmarks, side)
                    if source_angle is None or demo_angle is None:
                        failures.append(f"source_shape.{side}_elbow_angle_missing")
                        continue
                    delta = abs(demo_angle - source_angle)
                    metrics[f"source_shape.{side}_elbow_angle_delta"] = delta
                    if elbow_delta_limit is not None and delta > elbow_delta_limit:
                        failures.append(
                            f"source_shape.{side}_elbow_angle_delta={delta:.2f}_exceeds_{elbow_delta_limit:.2f}"
                        )

    return QualityAudit(failures=failures, metrics=metrics)


def format_delta(value: float | None) -> str:
    if value is None:
        return "n/a"
    return f"{value:.6f}"


def format_quality(
    profile: dict[str, Any],
    audit: QualityAudit,
    *,
    include_pending: bool,
) -> str:
    if not isinstance(profile.get("quality_gates"), dict):
        return "n/a"
    if audit.ok:
        return "ok"
    return "failed" if quality_gate_enforced(profile, include_pending=include_pending) else "pending_failed"


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
        "--tracking-gate",
        type=Path,
        default=repo_root / "Sources/CamiFitApp/AppExerciseTrackingGate.swift",
        help="Swift tracking gate that declares guideReadyPresetIDs and referenceCaptureRequiredPresetIDs",
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
    parser.add_argument(
        "--require-first-party-captures",
        action="store_true",
        help="legacy gate: fail until every packaged preset is backed by first-party captured reference data",
    )
    parser.add_argument(
        "--require-reference-clips",
        action="store_true",
        help="fail until every packaged preset is backed by accepted first-party or licensed external reference clips",
    )
    parser.add_argument(
        "--require-trackable-reference-clips",
        action="store_true",
        help="fail until every trackable/playable guide demo is backed by accepted first-party, protected-golden, or licensed external reference data",
    )
    parser.add_argument(
        "--require-guide-ready-inventory",
        action="store_true",
        help="fail unless packaged MotionDemos JSONLs exactly match AppExerciseTrackingGate.guideReadyPresetIDs",
    )
    parser.add_argument(
        "--enforce-pending-quality-gates",
        action="store_true",
        help="also fail pending reference traces when their declared motion-quality gates fail",
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
        capture = capture_status(profile)
        if is_pending_reference_capture(profile):
            pending.append(exercise_id)
        acceptance_failures = reference_acceptance_failures(
            profile,
            include_pending=args.enforce_pending_quality_gates,
        )
        for failure in acceptance_failures:
            failures.append(f"{exercise_id}: {failure}")
        manifest = load_manifest(demo_path)
        for failure in pending_source_search_failures(profile, manifest):
            failures.append(f"{exercise_id}: {failure}")
        if args.require_first_party_captures and not has_first_party_capture(profile):
            failures.append(f"{exercise_id}: capture status {capture} is not first-party reference data")
        if args.require_reference_clips and not has_accepted_reference_clip(profile):
            failures.append(f"{exercise_id}: capture status {capture} is not accepted reference clip data")
        if args.require_trackable_reference_clips and status_requires_demo(status) and not has_accepted_reference_clip(profile):
            failures.append(
                f"{exercise_id}: trackable guide status {status} has capture status {capture}, not accepted reference data"
            )
        requires_demo = status_requires_demo(status) or args.require_all_demos
        if not demo_path.exists():
            line = (
                f"motion-coverage exercise_id={exercise_id} profile={status} "
                f"capture={capture} demo=missing "
                f"normalizer={profile.get('normalizer', {}).get('status', 'unknown')}"
            )
            print(line)
            if requires_demo:
                failures.append(f"{exercise_id}: expected demo trace at {demo_path}")
            continue

        audit = audit_demo(demo_path, profile)
        quality = audit_quality_gates(profile, audit, manifest)
        quality_status = format_quality(
            profile,
            quality,
            include_pending=args.enforce_pending_quality_gates,
        )
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
            forced_loop_delta = finite_float(
                manifest.get("summary", {})
                .get("loop_closure", {})
                .get("max_endpoint_delta_before")
            )
            if forced_loop_delta is not None and forced_loop_delta > MAX_FORCED_LOOP_DELTA:
                manifest_errors.append(
                    f"forced_loop_delta={forced_loop_delta:.6f}_exceeds_{MAX_FORCED_LOOP_DELTA:.2f}"
                )
        manifest_errors.extend(manifest_reference_acceptance_failures(profile, manifest))
        print(
            f"motion-coverage exercise_id={exercise_id} profile={status} demo={'ok' if audit.ok else 'invalid'} "
            f"capture={capture} frames={audit.frame_count} "
            f"manifest={manifest_status}{'+' + ','.join(manifest_errors) if manifest_errors else ''} "
            f"quality={quality_status} "
            f"bounds={'invalid' if audit.out_of_bounds_landmarks else 'ok'} "
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
            if audit.timestamp_errors:
                failures.append(f"{exercise_id}: timestamp errors on lines {audit.timestamp_errors[:8]}")
            if audit.non_finite_values:
                failures.append(f"{exercise_id}: non-finite landmark values {audit.non_finite_values[:8]}")
            if audit.out_of_bounds_landmarks:
                failures.append(f"{exercise_id}: out-of-bounds landmarks {audit.out_of_bounds_landmarks[:8]}")
            if audit.missing_required:
                failures.append(f"{exercise_id}: missing required landmarks {audit.missing_required}")
            if audit.missing_contacts:
                failures.append(f"{exercise_id}: missing contact landmarks {audit.missing_contacts}")
            if audit.max_contact_delta is not None and audit.max_contact_delta > 0.001:
                failures.append(f"{exercise_id}: contact delta {audit.max_contact_delta:.6f} exceeds 0.001")
            if audit.max_loop_delta is not None and audit.max_loop_delta > 0.002:
                failures.append(f"{exercise_id}: loop delta {audit.max_loop_delta:.6f} exceeds 0.002")
        if quality.failures and quality_gate_enforced(
            profile,
            include_pending=args.enforce_pending_quality_gates,
        ):
            for failure in quality.failures[:12]:
                failures.append(f"{exercise_id}: quality gate {failure}")

    extra_profiles = sorted(set(profiles) - set(presets))
    for exercise_id in extra_profiles:
        print(f"motion-coverage exercise_id={exercise_id} preset=missing profile=extra")

    if args.strict:
        failures.extend(strict_fail_closed_inventory_failures(args.motion_demos, presets, profiles))
    if args.require_guide_ready_inventory:
        try:
            guide_ready_ids = load_swift_string_set(args.tracking_gate, "guideReadyPresetIDs")
            reference_capture_ids = load_swift_string_set(args.tracking_gate, "referenceCaptureRequiredPresetIDs")
        except (OSError, ValueError) as error:
            failures.append(f"guide-ready inventory could not load tracking gate: {error}")
            guide_ready_ids = set()
            reference_capture_ids = set()
        failures.extend(
            guide_ready_inventory_failures(
                args.motion_demos,
                presets,
                profiles,
                guide_ready_ids,
                reference_capture_ids,
            )
        )
        print(
            f"motion-coverage guide-ready-inventory guide_ready={len(guide_ready_ids)} "
            f"reference_capture_required={len(reference_capture_ids)} "
            f"playable_jsonls={len(list(args.motion_demos.glob('*.jsonl')))}"
        )

    print(
        f"motion-coverage summary presets={len(presets)} profiles={len(profiles)} "
        f"pending_reference_captures={len(pending)} failures={len(failures)}"
    )

    if failures and (args.strict or args.require_all_demos or args.require_guide_ready_inventory):
        for failure in failures:
            print(f"motion-coverage failure={failure}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
