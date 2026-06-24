#!/usr/bin/env python3
"""Generate portable motion-review gallery media for packaged demo traces."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MOTION_DEMOS = ROOT / "Sources" / "CamiFitApp" / "Resources" / "MotionDemos"
DEFAULT_TMP_REVIEW = ROOT / "tmp" / "motion-review"
DEFAULT_PUBLIC_REVIEW = ROOT / "website" / "public" / "motion-review-assets"
DEFAULT_SNAPSHOT = ROOT / "website" / "src" / "data" / "motionReviewSnapshot.json"
RENDERER = ROOT / "scripts" / "motion_reference" / "render_mediapipe_trace_review.py"


def public_media_url(exercise_id: str) -> str:
    return f"/motion-review-assets/{exercise_id}/mediapipe_skeleton_review.mp4"


def generated_video_path(public_dir: Path, exercise_id: str) -> Path:
    return public_dir / exercise_id / "mediapipe_skeleton_review.mp4"


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

    source = output_dir / "mediapipe_skeleton_review.mp4"
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

        media["contactSheetUrl"] = None
        media["sourceVideoUrl"] = None
        media["contactSheetBytes"] = None
        media["sourceVideoBytes"] = None

        video = generated_video_path(public_dir, exercise_id)
        if exercise_id in exercise_ids and video.exists():
            media["detectorVideoUrl"] = public_media_url(exercise_id)
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
            if generated_video_path(args.public_review_dir, raw_path.stem).exists()
        }

    snapshot = load_snapshot(args.snapshot)
    update_snapshot_media(snapshot, args.public_review_dir, generated_ids)
    write_snapshot(args.snapshot, snapshot)
    print(
        "motion-review gallery assets "
        f"traces={len(raw_paths)} review_videos={len(generated_ids)} snapshot={args.snapshot}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
