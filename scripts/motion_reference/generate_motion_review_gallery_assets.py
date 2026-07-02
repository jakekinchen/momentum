#!/usr/bin/env python3
"""Generate portable motion-review gallery media for packaged demo traces."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from pathlib import Path
from typing import Any

from update_motion_review_snapshot_traces import update_snapshot as update_snapshot_traces

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MOTION_DEMOS = ROOT / "Sources" / "CamiFitApp" / "Resources" / "MotionDemos"
DEFAULT_TMP_REVIEW = ROOT / "tmp" / "motion-review"
DEFAULT_PUBLIC_REVIEW = ROOT / "website" / "public" / "motion-review-assets"
DEFAULT_SNAPSHOT = ROOT / "website" / "src" / "data" / "motionReviewSnapshot.json"
RENDERER = ROOT / "scripts" / "motion_reference" / "render_mediapipe_trace_review.py"
SKELETON_REVIEW_FILENAME = "mediapipe_skeleton_review.mp4"
TRACE_REVIEW_FILENAME = "mediapipe_trace_review.mp4"
REVIEW_VIDEO_FILENAMES = (TRACE_REVIEW_FILENAME, SKELETON_REVIEW_FILENAME)


def public_media_url(exercise_id: str, filename: str = SKELETON_REVIEW_FILENAME) -> str:
    return f"/motion-review-assets/{exercise_id}/{filename}"


def generated_video_path(
    public_dir: Path,
    exercise_id: str,
    filename: str = SKELETON_REVIEW_FILENAME,
) -> Path:
    return public_dir / exercise_id / filename


def preferred_review_video(public_dir: Path, exercise_id: str) -> tuple[Path, str] | None:
    for filename in REVIEW_VIDEO_FILENAMES:
        path = generated_video_path(public_dir, exercise_id, filename)
        if path.exists():
            return path, filename
    return None


def packaged_trace_paths(motion_demos: Path) -> list[Path]:
    return sorted(motion_demos.glob("*.jsonl"))


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True)


def render_review_video(
    *,
    raw_path: Path,
    tmp_dir: Path,
    public_dir: Path,
    fps: int,
    width: int,
    height: int,
) -> Path:
    exercise_id = raw_path.stem
    output_dir = tmp_dir / exercise_id
    run(
        [
            "python3",
            str(RENDERER),
            "--raw",
            str(raw_path),
            "--output-dir",
            str(output_dir),
            "--fps",
            str(fps),
            "--width",
            str(width),
            "--height",
            str(height),
        ]
    )

    source = output_dir / SKELETON_REVIEW_FILENAME
    if not source.exists():
        raise FileNotFoundError(f"renderer did not create {source}")

    destination = generated_video_path(public_dir, exercise_id)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    return destination


def load_snapshot(snapshot_path: Path) -> dict[str, Any]:
    if not snapshot_path.exists():
        raise FileNotFoundError(f"missing motion review snapshot: {snapshot_path}")
    payload = json.loads(snapshot_path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict) or not isinstance(payload.get("exercises"), list):
        raise ValueError(f"invalid motion review snapshot: {snapshot_path}")
    return payload


def update_snapshot_media(snapshot: dict[str, Any], public_dir: Path, exercise_ids: set[str]) -> dict[str, Any]:
    detector_reviews = 0
    contact_sheets = 0
    for exercise in snapshot.get("exercises", []):
        if not isinstance(exercise, dict):
            continue
        exercise_id = exercise.get("id")
        media = exercise.get("media")
        if not isinstance(exercise_id, str) or not isinstance(media, dict):
            continue

        source_video_url = media.get("sourceVideoUrl")
        source_video_bytes = media.get("sourceVideoBytes")
        has_portable_source = isinstance(source_video_url, str) and source_video_url.startswith(("http://", "https://"))

        media["contactSheetUrl"] = None
        media["contactSheetBytes"] = None
        if has_portable_source:
            media["sourceVideoUrl"] = source_video_url
            media["sourceVideoBytes"] = source_video_bytes if isinstance(source_video_bytes, int) else None
        else:
            media["sourceVideoUrl"] = None
            media["sourceVideoBytes"] = None

        preferred_video = preferred_review_video(public_dir, exercise_id)
        if preferred_video is not None:
            video, filename = preferred_video
            media["detectorVideoUrl"] = public_media_url(exercise_id, filename)
            media["detectorVideoBytes"] = video.stat().st_size
            detector_reviews += 1
        else:
            media["detectorVideoUrl"] = None
            media["detectorVideoBytes"] = None

    summary = snapshot.setdefault("summary", {})
    if isinstance(summary, dict):
        summary["detectorReviews"] = detector_reviews
        summary["contactSheets"] = contact_sheets
    return snapshot


def write_snapshot(snapshot_path: Path, snapshot: dict[str, Any]) -> None:
    snapshot_path.parent.mkdir(parents=True, exist_ok=True)
    snapshot_path.write_text(json.dumps(snapshot, indent=2) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--motion-demos", type=Path, default=DEFAULT_MOTION_DEMOS)
    parser.add_argument("--tmp-review-dir", type=Path, default=DEFAULT_TMP_REVIEW)
    parser.add_argument("--public-review-dir", type=Path, default=DEFAULT_PUBLIC_REVIEW)
    parser.add_argument("--snapshot", type=Path, default=DEFAULT_SNAPSHOT)
    parser.add_argument("--fps", type=int, default=15)
    parser.add_argument("--width", type=int, default=540)
    parser.add_argument("--height", type=int, default=960)
    parser.add_argument("--skip-render", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    raw_paths = packaged_trace_paths(args.motion_demos)
    generated_ids: set[str] = set()

    if not args.skip_render:
        for raw_path in raw_paths:
            video = render_review_video(
                raw_path=raw_path,
                tmp_dir=args.tmp_review_dir,
                public_dir=args.public_review_dir,
                fps=args.fps,
                width=args.width,
                height=args.height,
            )
            generated_ids.add(raw_path.stem)
            print(f"motion-review media exercise={raw_path.stem} video={video}")
    else:
        generated_ids = {
            raw_path.stem
            for raw_path in raw_paths
            if preferred_review_video(args.public_review_dir, raw_path.stem) is not None
        }

    snapshot = load_snapshot(args.snapshot)
    update_snapshot_media(snapshot, args.public_review_dir, generated_ids)
    update_snapshot_traces(snapshot, args.motion_demos, {raw_path.stem for raw_path in raw_paths})
    write_snapshot(args.snapshot, snapshot)
    print(
        "motion-review gallery assets "
        f"traces={len(raw_paths)} review_videos={len(generated_ids)} snapshot={args.snapshot}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
