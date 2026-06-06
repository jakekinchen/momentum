#!/usr/bin/env python3
"""Extract raw MediaPipe pose JSONL from a trainer reference video."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_ROOT = ROOT / "dist" / "motion-reference"
DEFAULT_WORKER = ROOT / "pose_worker" / "pose_worker.py"
DEFAULT_MODEL = ROOT / "pose_worker" / "models" / "pose_landmarker_lite.task"
REPO_PYTHON = ROOT / ".venv" / "bin" / "python"


def default_python() -> Path:
    if os.environ.get("CAMIFIT_PYTHON"):
        return Path(os.environ["CAMIFIT_PYTHON"]).expanduser()
    if REPO_PYTHON.exists():
        return REPO_PYTHON
    return Path(sys.executable)


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True)


def python_worker_env(python: Path) -> dict[str, str]:
    env = os.environ.copy()
    # macOS/Python launcher state can leak from the parent interpreter into a
    # child venv and make site-packages such as mediapipe disappear.
    for key in ("__PYVENV_LAUNCHER__", "PYTHONHOME", "PYTHONPATH"):
        env.pop(key, None)
    if python.parent.name == "bin" and (python.parent.parent / "pyvenv.cfg").exists():
        venv = python.parent.parent
        env["VIRTUAL_ENV"] = str(venv)
        env["PATH"] = str(python.parent) + os.pathsep + env.get("PATH", "")
    elif python.is_absolute() and python.parent.exists():
        env["PATH"] = str(python.parent) + os.pathsep + env.get("PATH", "")
    return env


def seconds(ms: int | None) -> str:
    return f"{(ms or 0) / 1000:.3f}"


def extract_frames(args: argparse.Namespace, frame_dir: Path) -> list[Path]:
    if not shutil.which(args.ffmpeg):
        raise SystemExit(f"ffmpeg not found: {args.ffmpeg}")

    if frame_dir.exists():
        shutil.rmtree(frame_dir)
    frame_dir.mkdir(parents=True)

    cmd = [args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y"]
    if args.start_ms is not None:
        cmd += ["-ss", seconds(args.start_ms)]
    cmd += ["-i", str(args.video)]
    if args.end_ms is not None:
        duration_ms = args.end_ms - (args.start_ms or 0)
        if duration_ms <= 0:
            raise SystemExit("--end-ms must be greater than --start-ms")
        cmd += ["-t", seconds(duration_ms)]
    cmd += ["-vf", f"fps={args.fps}", str(frame_dir / "frame_%06d.jpg")]
    run(cmd)

    frames = sorted(frame_dir.glob("frame_*.jpg"))
    if not frames:
        raise SystemExit(f"ffmpeg produced no frames in {frame_dir}")
    return frames


def read_worker_response(process: subprocess.Popen[str]) -> dict[str, Any]:
    assert process.stdout is not None
    line = process.stdout.readline()
    if not line:
        stderr = process.stderr.read() if process.stderr is not None else ""
        raise RuntimeError(f"pose worker exited without a response\n{stderr}")
    response = json.loads(line)
    if response.get("type") == "error":
        raise RuntimeError(response.get("error", "pose worker error"))
    return response


def write_raw_trace(args: argparse.Namespace, frames: list[Path], raw_path: Path) -> None:
    cmd = [
        str(args.python),
        str(args.worker),
        "--mode",
        "mediapipe",
        "--model",
        str(args.model),
    ]
    process = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=python_worker_env(args.python),
        text=True,
        bufsize=1,
    )
    assert process.stdin is not None

    try:
        process.stdin.write(json.dumps({"type": "health"}) + "\n")
        process.stdin.flush()
        health = read_worker_response(process)
        if not health.get("pose_ready"):
            raise RuntimeError(health.get("message", "pose worker not ready"))

        with raw_path.open("w", encoding="utf-8") as out:
            for index, frame in enumerate(frames):
                request = {
                    "type": "predict",
                    "frame_id": index,
                    "timestamp_ms": round(index * 1000 / args.fps),
                    "image_path": str(frame),
                }
                process.stdin.write(json.dumps(request, separators=(",", ":")) + "\n")
                process.stdin.flush()
                response = read_worker_response(process)
                out.write(json.dumps(response, separators=(",", ":")) + "\n")
    finally:
        try:
            process.stdin.close()
        except Exception:
            pass
        process.wait(timeout=10)


def write_manifest(args: argparse.Namespace, output_dir: Path, frame_count: int) -> None:
    manifest = {
        "exercise_id": args.exercise_id,
        "source_video": str(args.video),
        "fps": args.fps,
        "start_ms": args.start_ms,
        "end_ms": args.end_ms,
        "frame_count": frame_count,
        "raw_trace": "raw_mediapipe.jsonl",
        "worker": str(args.worker),
        "model": str(args.model),
        "next_step": (
            "scripts/motion_reference/normalize_lunge_trace.py "
            f"--raw {output_dir / 'raw_mediapipe.jsonl'} "
            f"--output {output_dir / (args.exercise_id + '.jsonl')} --front-side right"
        ),
    }
    (output_dir / "motion_reference_manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n",
        encoding="utf-8",
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video", type=Path, required=True, help="trainer reference video")
    parser.add_argument("--exercise-id", default="bodyweight_lunge")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--fps", type=int, default=15)
    parser.add_argument("--start-ms", type=int)
    parser.add_argument("--end-ms", type=int)
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--python", type=Path, default=default_python())
    parser.add_argument("--worker", type=Path, default=DEFAULT_WORKER)
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    args.video = args.video.expanduser().resolve()
    args.python = args.python.expanduser()
    args.worker = args.worker.expanduser().resolve()
    args.model = args.model.expanduser().resolve()
    output_dir = (args.output_dir or DEFAULT_OUTPUT_ROOT / args.exercise_id).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    frames = extract_frames(args, output_dir / "frames")
    raw_path = output_dir / "raw_mediapipe.jsonl"
    write_raw_trace(args, frames, raw_path)
    write_manifest(args, output_dir, len(frames))
    print(f"motion-reference raw_trace={raw_path} frames={len(frames)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
