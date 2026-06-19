#!/usr/bin/env python3
"""Extract raw MediaPipe pose JSONL from a trainer reference video."""

from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_ROOT = ROOT / "dist" / "motion-reference"
DEFAULT_WORKER = ROOT / "pose_worker" / "pose_worker.py"
DEFAULT_MODEL = ROOT / "pose_worker" / "models" / "pose_landmarker_lite.task"
DEFAULT_PROFILES = ROOT / "scripts" / "motion_reference" / "exercise_motion_profiles.json"
REPO_PYTHON = ROOT / ".venv" / "bin" / "python"


def default_python() -> Path:
    if os.environ.get("CAMIFIT_PYTHON"):
        return Path(os.environ["CAMIFIT_PYTHON"]).expanduser()
    if REPO_PYTHON.exists():
        return REPO_PYTHON
    return Path(sys.executable)


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True)


def shell_command(parts: list[str | Path]) -> str:
    return " ".join(shlex.quote(str(part)) for part in parts)


def load_profiles(path: Path) -> dict[str, dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    profiles: dict[str, dict[str, Any]] = {}
    for profile in payload.get("profiles", []):
        exercise_id = profile.get("exercise_id")
        if isinstance(exercise_id, str) and exercise_id:
            profiles[exercise_id] = profile
    return profiles


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


def normalizer_step(
    args: argparse.Namespace,
    output_dir: Path,
    profile: dict[str, Any] | None,
) -> dict[str, Any]:
    raw_path = output_dir / "raw_mediapipe.jsonl"
    output_path = output_dir / f"{args.exercise_id}.normalized.jsonl"
    normalizer = profile.get("normalizer", {}) if isinstance(profile, dict) else {}
    script = str(normalizer.get("script", "")) if isinstance(normalizer, dict) else ""
    if not script:
        return {
            "type": "normalize",
            "status": "blocked",
            "reason": "missing_motion_profile_normalizer",
        }
    if script == "scripts/motion_reference/compile_archetype_trace.py":
        return {
            "type": "normalize",
            "status": "blocked",
            "script": script,
            "reason": "profile_still_uses_synthetic_archetype_trace; add a reference-clip normalizer before packaging this capture as guide-ready",
        }

    command: list[str | Path] = [
        script,
        "--raw",
        raw_path,
        "--output",
        output_path,
        "--exercise-id",
        args.exercise_id,
    ]
    script_name = Path(script).name
    if script_name in {"normalize_squat_trace.py", "normalize_pushup_trace.py", "normalize_jumping_jack_trace.py"}:
        command.extend(["--video", args.video])
    if script_name == "normalize_lunge_trace.py":
        command.extend(["--front-side", "right"])
    if script_name == "normalize_plank_trace.py":
        capture = profile.get("capture", {}) if isinstance(profile, dict) else {}
        command.extend(
            [
                "--primary-side",
                str(capture.get("primary_side", "auto")).replace("_camera_side", ""),
                "--source-label",
                str(capture.get("clip", args.exercise_id)),
                "--source-page",
                str(capture.get("source_page", "")),
                "--source-media-url",
                str(capture.get("source_media_url", "")),
                "--source-video",
                args.video,
                "--source-license",
                str(capture.get("source_license", "")),
                "--source-attribution",
                str(capture.get("source_attribution", "")),
            ]
        )
    if script_name == "normalize_pike_trace.py":
        capture = profile.get("capture", {}) if isinstance(profile, dict) else {}
        command.extend(
            [
                "--primary-side",
                str(capture.get("primary_side", "auto")).replace("_camera_side", ""),
                "--fit-viewport",
                "--source-start-ms",
                str(args.start_ms or 0),
                "--source-label",
                str(capture.get("clip", args.exercise_id)),
                "--source-page",
                str(capture.get("source_page", "")),
                "--source-media-url",
                str(capture.get("source_media_url", "")),
                "--source-video",
                args.video,
                "--source-license",
                str(capture.get("source_license", "")),
                "--source-attribution",
                str(capture.get("source_attribution", "")),
            ]
        )

    return {
        "type": "normalize",
        "status": "available",
        "script": script,
        "output_trace": str(output_path),
        "command": shell_command(command),
    }


def profile_summary(profile: dict[str, Any] | None) -> dict[str, Any]:
    if profile is None:
        return {
            "status": "missing",
        }
    capture = profile.get("capture", {})
    normalizer = profile.get("normalizer", {})
    return {
        "status": "found",
        "viewer_status": profile.get("viewer_status"),
        "measurement_status": profile.get("measurement_status"),
        "capture_status": capture.get("status") if isinstance(capture, dict) else None,
        "required_view": capture.get("required_view") if isinstance(capture, dict) else None,
        "normalizer_status": normalizer.get("status") if isinstance(normalizer, dict) else None,
        "normalizer_script": normalizer.get("script") if isinstance(normalizer, dict) else None,
        "required_output_landmarks": profile.get("required_output_landmarks", []),
        "required_contacts": profile.get("required_contacts", []),
        "qa_gates": profile.get("qa_gates", []),
    }


def write_manifest(
    args: argparse.Namespace,
    output_dir: Path,
    frame_count: int,
    profile: dict[str, Any] | None,
) -> None:
    raw_path = output_dir / "raw_mediapipe.jsonl"
    raw_review_dir = output_dir / "raw_review"
    raw_review_command: list[str | Path] = [
        "scripts/motion_reference/render_mediapipe_trace_review.py",
        "--raw",
        raw_path,
        "--video",
        args.video,
        "--output-dir",
        raw_review_dir,
        "--fps",
        str(args.fps),
    ]
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
        "profile": profile_summary(profile),
        "next_steps": [
            {
                "type": "review_raw_trace",
                "status": "available",
                "output_dir": str(raw_review_dir),
                "command": shell_command(raw_review_command),
            },
            normalizer_step(args, output_dir, profile),
        ],
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
    parser.add_argument("--profiles", type=Path, default=DEFAULT_PROFILES)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    args.video = args.video.expanduser().resolve()
    args.python = args.python.expanduser()
    args.worker = args.worker.expanduser().resolve()
    args.model = args.model.expanduser().resolve()
    args.profiles = args.profiles.expanduser().resolve()
    output_dir = (args.output_dir or DEFAULT_OUTPUT_ROOT / args.exercise_id).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    profile = load_profiles(args.profiles).get(args.exercise_id)

    frames = extract_frames(args, output_dir / "frames")
    raw_path = output_dir / "raw_mediapipe.jsonl"
    write_raw_trace(args, frames, raw_path)
    write_manifest(args, output_dir, len(frames), profile)
    print(f"motion-reference raw_trace={raw_path} frames={len(frames)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
