#!/usr/bin/env python3
"""Render a MediaPipe pose JSONL review video without image libraries."""

from __future__ import annotations

import argparse
import json
import math
import shutil
import subprocess
from pathlib import Path
from typing import Any

POSE_CONNECTIONS = [
    (11, 12),
    (11, 23),
    (12, 24),
    (23, 24),
    (11, 13),
    (13, 15),
    (15, 17),
    (15, 19),
    (15, 21),
    (12, 14),
    (14, 16),
    (16, 18),
    (16, 20),
    (16, 22),
    (23, 25),
    (25, 27),
    (27, 29),
    (29, 31),
    (24, 26),
    (26, 28),
    (28, 30),
    (30, 32),
]

KEY_LANDMARKS = {11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28, 31, 32}
DEMO_SIDE_CONNECTIONS = [
    ("shoulder", "elbow"),
    ("elbow", "wrist"),
    ("shoulder", "hip"),
    ("hip", "knee"),
    ("knee", "ankle"),
    ("ankle", "heel"),
    ("ankle", "foot.index"),
    ("heel", "foot.index"),
]


class Canvas:
    def __init__(self, width: int, height: int) -> None:
        self.width = width
        self.height = height
        self.pixels = bytearray(width * height * 3)

    def fill(self) -> None:
        for y in range(self.height):
            yy = y / max(self.height - 1, 1)
            for x in range(self.width):
                xx = x / max(self.width - 1, 1)
                glow = 0.22 * math.exp(-((xx - 0.48) ** 2 / 0.11 + (yy - 0.50) ** 2 / 0.18))
                color = (
                    int(5 + 16 * xx + 74 * glow),
                    int(12 + 52 * (1 - xx) + 92 * glow),
                    int(13 + 48 * (1 - yy) + 82 * glow),
                )
                self.set_pixel(x, y, color)

    def set_pixel(self, x: int, y: int, color: tuple[int, int, int]) -> None:
        if x < 0 or y < 0 or x >= self.width or y >= self.height:
            return
        i = (y * self.width + x) * 3
        self.pixels[i : i + 3] = bytes(color)

    def blend_pixel(self, x: int, y: int, color: tuple[int, int, int], alpha: float) -> None:
        if x < 0 or y < 0 or x >= self.width or y >= self.height:
            return
        i = (y * self.width + x) * 3
        inv = 1 - alpha
        self.pixels[i] = max(0, min(255, int(self.pixels[i] * inv + color[0] * alpha)))
        self.pixels[i + 1] = max(0, min(255, int(self.pixels[i + 1] * inv + color[1] * alpha)))
        self.pixels[i + 2] = max(0, min(255, int(self.pixels[i + 2] * inv + color[2] * alpha)))

    def circle(self, x: float, y: float, radius: float, color: tuple[int, int, int], alpha: float) -> None:
        cx, cy = int(round(x)), int(round(y))
        r = int(math.ceil(radius))
        rr = radius * radius
        for py in range(cy - r, cy + r + 1):
            for px in range(cx - r, cx + r + 1):
                if (px - x) ** 2 + (py - y) ** 2 <= rr:
                    self.blend_pixel(px, py, color, alpha)

    def line(
        self,
        a: tuple[float, float],
        b: tuple[float, float],
        radius: float,
        color: tuple[int, int, int],
        alpha: float,
    ) -> None:
        dx = b[0] - a[0]
        dy = b[1] - a[1]
        steps = max(1, int(math.hypot(dx, dy) / max(radius * 0.75, 2)))
        for step in range(steps + 1):
            t = step / steps
            self.circle(a[0] + dx * t, a[1] + dy * t, radius, color, alpha)

    def rect(self, x0: int, y0: int, x1: int, y1: int, color: tuple[int, int, int], alpha: float) -> None:
        for y in range(y0, y1):
            for x in range(x0, x1):
                self.blend_pixel(x, y, color, alpha)

    def write_ppm(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("wb") as handle:
            handle.write(f"P6\n{self.width} {self.height}\n255\n".encode("ascii"))
            handle.write(self.pixels)


def load_rows(raw_path: Path) -> list[dict[str, Any]]:
    rows = []
    with raw_path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def point(landmark: dict[str, Any], width: int, height: int) -> tuple[float, float]:
    return (float(landmark["x"]) * width, float(landmark["y"]) * height)


def draw_raw_pose(canvas: Canvas, landmarks: list[dict[str, Any]], width: int, height: int) -> None:
    canvas.rect(0, height - 4, width, height, (255, 220, 122), 0.45)
    for a_index, b_index in POSE_CONNECTIONS:
        a = landmarks[a_index]
        b = landmarks[b_index]
        visibility = min(float(a.get("visibility", 1)), float(b.get("visibility", 1)))
        color = (222, 255, 250) if visibility >= 0.55 else (96, 116, 122)
        alpha = 0.96 if visibility >= 0.55 else 0.42
        radius = 5 if visibility >= 0.55 else 3
        canvas.line(point(a, width, height), point(b, width, height), radius, color, alpha)

    for index, landmark in enumerate(landmarks):
        visibility = float(landmark.get("visibility", 1))
        if index not in KEY_LANDMARKS and visibility < 0.55:
            continue
        color = (91, 246, 236) if index in KEY_LANDMARKS and visibility >= 0.55 else (255, 233, 142)
        radius = 7 if index in KEY_LANDMARKS else 4
        canvas.circle(*point(landmark, width, height), radius, color, 0.96)


def draw_motion_demo_pose(canvas: Canvas, landmarks: dict[str, dict[str, Any]], width: int, height: int) -> None:
    canvas.rect(0, height - 4, width, height, (255, 220, 122), 0.45)
    for a_name, b_name in demo_connections(landmarks):
        if a_name not in landmarks or b_name not in landmarks:
            continue
        a = landmarks[a_name]
        b = landmarks[b_name]
        role = semantic_role(a_name, b_name)
        color = demo_color(role)
        radius = 4 if role in {"secondary", "left"} else 6
        alpha = 0.48 if role == "secondary" else 0.86
        canvas.line(point(a, width, height), point(b, width, height), radius, color, alpha)

    for name in demo_point_names(landmarks):
        landmark = landmarks[name]
        if not (
            name == "nose"
            or name.startswith("primary.")
            or name.startswith("secondary.")
            or name.startswith("left.")
            or name.startswith("right.")
        ):
            continue
        role = semantic_role(name)
        color = demo_color(role)
        radius = 7 if role in {"primary", "right"} else 5
        canvas.circle(*point(landmark, width, height), radius, color, 0.94)


def demo_connections(landmarks: dict[str, dict[str, Any]]) -> list[tuple[str, str]]:
    if all(f"{side}.shoulder" in landmarks for side in ("left", "right")):
        return [
            ("left.shoulder", "right.shoulder"),
            ("left.hip", "right.hip"),
        ] + [
            (f"{prefix}.{a}", f"{prefix}.{b}")
            for prefix in ("left", "right")
            for a, b in DEMO_SIDE_CONNECTIONS
        ]

    return [
        ("primary.shoulder", "secondary.shoulder"),
        ("primary.hip", "secondary.hip"),
    ] + [
        (f"{prefix}.{a}", f"{prefix}.{b}")
        for prefix in ("primary", "secondary")
        for a, b in DEMO_SIDE_CONNECTIONS
    ]


def demo_point_names(landmarks: dict[str, dict[str, Any]]) -> list[str]:
    if any(name.startswith("left.") or name.startswith("right.") for name in landmarks):
        prefixes = ("left.", "right.")
    else:
        prefixes = ("primary.", "secondary.")
    names = ["nose"] if "nose" in landmarks else []
    names.extend(
        name
        for name in landmarks
        if name.startswith(prefixes)
    )
    return names


def semantic_role(*names: str) -> str:
    joined = " ".join(names)
    if "secondary." in joined:
        return "secondary"
    if "left." in joined and "right." not in joined:
        return "left"
    if "right." in joined and "left." not in joined:
        return "right"
    return "primary"


def demo_color(role: str) -> tuple[int, int, int]:
    if role == "secondary":
        return (126, 160, 162)
    if role == "left":
        return (255, 233, 142)
    if role == "right":
        return (91, 246, 236)
    return (222, 255, 250)


def render_skeleton_frames(rows: list[dict[str, Any]], frame_dir: Path, width: int, height: int) -> None:
    if frame_dir.exists():
        shutil.rmtree(frame_dir)
    frame_dir.mkdir(parents=True)

    for frame_index, row in enumerate(rows):
        canvas = Canvas(width, height)
        canvas.fill()
        landmarks = row.get("landmarks") or []
        if isinstance(landmarks, list) and len(landmarks) == 33:
            draw_raw_pose(canvas, landmarks, width, height)
        elif isinstance(landmarks, dict):
            draw_motion_demo_pose(canvas, landmarks, width, height)

        canvas.write_ppm(frame_dir / f"frame_{frame_index:06d}.ppm")


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True)


def encode_review(
    *,
    frame_dir: Path,
    video_path: Path | None,
    skeleton_output: Path,
    review_output: Path,
    fps: int,
    width: int,
    height: int,
) -> None:
    run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-framerate",
            str(fps),
            "-i",
            str(frame_dir / "frame_%06d.ppm"),
            "-pix_fmt",
            "yuv420p",
            str(skeleton_output),
        ]
    )

    if video_path is None:
        return

    run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(video_path),
            "-i",
            str(skeleton_output),
            "-filter_complex",
            (
                f"[0:v]fps={fps},scale={width}:{height}:force_original_aspect_ratio=decrease,"
                f"pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:black,setpts=PTS-STARTPTS[left];"
                f"[1:v]scale={width}:{height},setpts=PTS-STARTPTS[right];"
                "[left][right]hstack=inputs=2[v]"
            ),
            "-map",
            "[v]",
            "-shortest",
            "-pix_fmt",
            "yuv420p",
            str(review_output),
        ]
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw", type=Path, required=True)
    parser.add_argument("--video", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--fps", type=int, default=15)
    parser.add_argument("--width", type=int, default=540)
    parser.add_argument("--height", type=int, default=960)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    raw_path = args.raw.expanduser().resolve()
    video_path = args.video.expanduser().resolve() if args.video else None
    output_dir = (args.output_dir or raw_path.parent).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    rows = load_rows(raw_path)
    frame_dir = output_dir / "review_skeleton_frames"
    skeleton_output = output_dir / "mediapipe_skeleton_review.mp4"
    review_output = output_dir / "mediapipe_trace_review.mp4"
    render_skeleton_frames(rows, frame_dir, args.width, args.height)
    encode_review(
        frame_dir=frame_dir,
        video_path=video_path,
        skeleton_output=skeleton_output,
        review_output=review_output,
        fps=args.fps,
        width=args.width,
        height=args.height,
    )
    print(f"motion-reference skeleton_review={skeleton_output}")
    if video_path is not None:
        print(f"motion-reference trace_review={review_output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
