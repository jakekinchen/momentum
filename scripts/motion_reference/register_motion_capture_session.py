#!/usr/bin/env python3
"""Register first-party motion capture files for the motion-data factory.

The command copies source files into ignored `dist/motion-reference/...`
storage, writes capture/review JSON sidecars, and emits a manifest patch. It
does not promote exercises or write app MotionDemos JSONL files.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_ROOT = ROOT / "dist" / "motion-reference"
SAFE_TOKEN = re.compile(r"^[a-z0-9_]+$")


@dataclass(frozen=True)
class SourceInput:
    view: str
    path: Path


def safe_token(value: str, label: str) -> str:
    if not SAFE_TOKEN.fullmatch(value):
        raise ValueError(f"{label} must match {SAFE_TOKEN.pattern}: {value}")
    return value


def repo_path(path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(ROOT).as_posix()
    except ValueError:
        return str(resolved)


def sha256_hex(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_source(value: str) -> SourceInput:
    if "=" not in value:
        raise argparse.ArgumentTypeError("source must be VIEW=/path/to/source.mp4")
    view, raw_path = value.split("=", 1)
    try:
        safe_token(view, "source view")
    except ValueError as error:
        raise argparse.ArgumentTypeError(str(error)) from error
    path = Path(raw_path).expanduser()
    if not path.exists() or not path.is_file():
        raise argparse.ArgumentTypeError(f"source file does not exist: {path}")
    return SourceInput(view=view, path=path)


def parse_resolution(value: str) -> dict[str, int] | str:
    if "x" not in value:
        return value
    width, height = value.lower().split("x", 1)
    try:
        return {"width": int(width), "height": int(height)}
    except ValueError as error:
        raise argparse.ArgumentTypeError("resolution must be WIDTHxHEIGHT or a label") from error


def copy_sources(
    *,
    exercise_id: str,
    session_dir: Path,
    sources: list[SourceInput],
    force: bool,
) -> list[dict[str, Any]]:
    copied: list[dict[str, Any]] = []
    seen_views: set[str] = set()
    session_dir.mkdir(parents=True, exist_ok=True)

    for source in sources:
        if source.view in seen_views:
            raise ValueError(f"duplicate source view: {source.view}")
        seen_views.add(source.view)

        destination = session_dir / f"source_{source.view}{source.path.suffix.lower()}"
        if destination.exists() and not force:
            raise FileExistsError(f"refusing to overwrite existing source: {destination}")
        shutil.copy2(source.path, destination)
        copied.append(
            {
                "view": source.view,
                "path": repo_path(destination),
                "sha256": sha256_hex(destination),
                "bytes": destination.stat().st_size,
            }
        )

    if not copied:
        raise ValueError(f"no source files registered for {exercise_id}")
    return copied


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def register_capture_session(
    *,
    exercise_id: str,
    session_id: str,
    sources: list[SourceInput],
    output_root: Path,
    source_kind: str,
    manifest_source_kind: str,
    source_label: str,
    source_page: str,
    source_media_url: str,
    source_license: str,
    source_attribution: str,
    camera_view: str,
    fps: float,
    resolution: dict[str, int] | str,
    equipment: str,
    performer_notes: str,
    reviewer_notes: str,
    force: bool = False,
) -> dict[str, Any]:
    safe_token(exercise_id, "exercise id")
    safe_token(session_id, "session id")

    session_dir = output_root / exercise_id / session_id
    source_files = copy_sources(
        exercise_id=exercise_id,
        session_dir=session_dir,
        sources=sources,
        force=force,
    )

    capture_session = {
        "exercise_id": exercise_id,
        "session_id": session_id,
        "source_kind": source_kind,
        "camera_view": camera_view,
        "fps": fps,
        "resolution": resolution,
        "equipment": equipment,
        "license": source_license,
        "attribution": source_attribution,
        "source_page": source_page,
        "source_media_url": source_media_url,
        "performer_notes": performer_notes,
        "reviewer_notes": reviewer_notes,
        "source_files": source_files,
    }
    visual_review = {
        "exercise_id": exercise_id,
        "session_id": session_id,
        "status": "pending",
        "reviewer": "",
        "reviewed_at": "",
        "evidence": "Capture registered. Source, detector, and avatar review are still pending.",
        "source_video_reviewed": False,
        "detector_video_reviewed": False,
        "avatar_motion_reviewed": False,
        "checks": {
            "anatomically_plausible": False,
            "phase_matches_source": False,
            "contact_points_stable": False,
            "no_limb_identity_flips": False,
            "loop_boundary_stable": False,
            "source_provenance_present": False,
        },
        "failure_reasons": [],
        "notes": "",
    }

    capture_path = session_dir / "capture_session.json"
    visual_review_path = session_dir / "visual_review.json"
    write_json(capture_path, capture_session)
    write_json(visual_review_path, visual_review)

    preferred_source = next(
        (item for item in source_files if item["view"] == "side"),
        source_files[0],
    )
    manifest_patch = {
        "exercise_id": exercise_id,
        "source_kind": manifest_source_kind,
        "source_label": source_label,
        "source_page": source_page,
        "source_media_url": source_media_url,
        "source_video": preferred_source["path"],
        "source_license": source_license,
        "source_attribution": source_attribution,
        "capture_session_path": repo_path(capture_path),
        "visual_review_path": repo_path(visual_review_path),
        "artifact_integrity": {
            f"source_{item['view']}": {
                "bytes": item["bytes"],
                "sha256": item["sha256"],
            }
            for item in source_files
        },
    }
    report = {
        "exercise_id": exercise_id,
        "session_id": session_id,
        "session_dir": repo_path(session_dir),
        "capture_session_path": repo_path(capture_path),
        "visual_review_path": repo_path(visual_review_path),
        "source_files": source_files,
        "manifest_patch": manifest_patch,
        "promotion_state": "not_promoted",
        "next_action": "Run detector extraction and scorecards, then complete visual review before any guide-ready promotion.",
    }
    write_json(session_dir / "registration_report.json", report)
    return report


def default_session_id() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ").lower()


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exercise-id", required=True)
    parser.add_argument("--session-id", default=default_session_id())
    parser.add_argument("--source", action="append", type=parse_source, required=True)
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT_ROOT)
    parser.add_argument("--source-kind", default="first_party_trainer_capture")
    parser.add_argument("--manifest-source-kind", default=None)
    parser.add_argument("--source-label", required=True)
    parser.add_argument("--source-page", default="")
    parser.add_argument("--source-media-url", default="")
    parser.add_argument("--camera-view", required=True)
    parser.add_argument("--fps", type=float, required=True)
    parser.add_argument("--resolution", type=parse_resolution, required=True)
    parser.add_argument("--equipment", required=True)
    parser.add_argument(
        "--source-license",
        "--license",
        dest="source_license",
        default="First-party CamiFit trainer capture",
    )
    parser.add_argument("--source-attribution", default="")
    parser.add_argument("--performer-notes", default="")
    parser.add_argument("--reviewer-notes", required=True)
    parser.add_argument("--force", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    report = register_capture_session(
        exercise_id=args.exercise_id,
        session_id=args.session_id,
        sources=args.source,
        output_root=args.output_root,
        source_kind=args.source_kind,
        manifest_source_kind=args.manifest_source_kind or args.source_kind,
        source_label=args.source_label,
        source_page=args.source_page,
        source_media_url=args.source_media_url,
        source_license=args.source_license,
        source_attribution=args.source_attribution,
        camera_view=args.camera_view,
        fps=args.fps,
        resolution=args.resolution,
        equipment=args.equipment,
        performer_notes=args.performer_notes,
        reviewer_notes=args.reviewer_notes,
        force=args.force,
    )
    print(
        "motion-capture-session "
        f"exercise={report['exercise_id']} session={report['session_id']} "
        f"capture_session={report['capture_session_path']}"
    )
    print(json.dumps(report["manifest_patch"], indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
