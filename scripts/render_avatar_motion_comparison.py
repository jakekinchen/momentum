#!/usr/bin/env python3
"""Render avatar motion-source comparison videos.

This intentionally keeps dependencies to Python stdlib + ffmpeg. It renders:

- a trainer-reference lane prototype that shows the target biomechanics for a
  future "trainer video -> MediaPipe -> PoseFrame" clip;
- a dataset lane from the public UI-PRMD inline-lunge sample mirrored in
  tejas1904/UI-PRMD-Visualize-python-port;
- a side-by-side comparison.
"""

from __future__ import annotations

import math
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "dist" / "avatar-motion-comparison"
FRAME_DIR = OUT_DIR / "frames"
FPS = 15
DURATION_SECONDS = 4
FRAME_COUNT = FPS * DURATION_SECONDS
PANEL_W = 720
PANEL_H = 810
SIDE_W = PANEL_W * 2
SIDE_H = PANEL_H

GLYPHS = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01111", "10000", "10000", "10011", "10001", "10001", "01110"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
    "6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
    "?": ["11110", "00001", "00010", "00100", "00100", "00000", "00100"],
}


def clamp(value: int, low: int, high: int) -> int:
    return max(low, min(high, value))


class Canvas:
    def __init__(self, width: int, height: int, background: bytearray | None = None) -> None:
        self.width = width
        self.height = height
        self.pixels = bytearray(background) if background is not None else bytearray(width * height * 3)

    def fill_gradient(self, left: tuple[int, int, int], right: tuple[int, int, int]) -> None:
        for y in range(self.height):
            yy = y / max(self.height - 1, 1)
            for x in range(self.width):
                xx = x / max(self.width - 1, 1)
                glow = 0.18 * math.exp(-((xx - 0.50) ** 2 / 0.11 + (yy - 0.47) ** 2 / 0.18))
                color = []
                for i in range(3):
                    base = left[i] * (1 - xx) + right[i] * xx
                    color.append(clamp(int(base + 70 * glow), 0, 255))
                self.set_pixel(x, y, tuple(color))

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
        self.pixels[i] = clamp(int(self.pixels[i] * inv + color[0] * alpha), 0, 255)
        self.pixels[i + 1] = clamp(int(self.pixels[i + 1] * inv + color[1] * alpha), 0, 255)
        self.pixels[i + 2] = clamp(int(self.pixels[i + 2] * inv + color[2] * alpha), 0, 255)

    def circle(self, x: float, y: float, radius: float, color: tuple[int, int, int], alpha: float = 1) -> None:
        r = int(math.ceil(radius))
        cx, cy = int(round(x)), int(round(y))
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
        alpha: float = 1,
    ) -> None:
        dx = b[0] - a[0]
        dy = b[1] - a[1]
        steps = max(1, int(math.hypot(dx, dy) / max(radius * 0.8, 2)))
        for step in range(steps + 1):
            t = step / steps
            self.circle(a[0] + dx * t, a[1] + dy * t, radius, color, alpha)

    def rect(self, x0: int, y0: int, x1: int, y1: int, color: tuple[int, int, int], alpha: float) -> None:
        for y in range(y0, y1):
            for x in range(x0, x1):
                self.blend_pixel(x, y, color, alpha)

    def draw_text(self, text: str, x: int, y: int, scale: int, color: tuple[int, int, int]) -> None:
        cursor = x
        for ch in text.upper():
            if ch == " ":
                cursor += 4 * scale
                continue
            glyph = GLYPHS.get(ch, GLYPHS["?"])
            for gy, row in enumerate(glyph):
                for gx, cell in enumerate(row):
                    if cell == "1":
                        self.rect(
                            cursor + gx * scale,
                            y + gy * scale,
                            cursor + (gx + 1) * scale,
                            y + (gy + 1) * scale,
                            color,
                            0.94,
                        )
            cursor += 6 * scale

    def write_ppm(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("wb") as f:
            f.write(f"P6\n{self.width} {self.height}\n255\n".encode("ascii"))
            f.write(self.pixels)


def text_width(text: str, scale: int) -> int:
    width = 0
    for ch in text.upper():
        width += 4 * scale if ch == " " else 6 * scale
    return max(0, width - scale)


def draw_label(canvas: Canvas, text: str, x: int, y: int, scale: int) -> None:
    width = text_width(text, scale)
    height = 7 * scale
    canvas.rect(x - 12, y - 9, x + width + 12, y + height + 9, (0, 0, 0), 0.34)
    canvas.draw_text(text, x, y, scale, (243, 251, 250))


def trainer_reference_points(frame: int, panel_x: int = 0) -> dict[str, tuple[float, float]]:
    phase = (frame % (FPS * 3)) / (FPS * 3)
    factor = math.sin(math.pi * phase)
    ease = factor * factor * (3 - 2 * factor)
    bounce = 4 * math.sin(2 * math.pi * phase)

    def p(x: float, y: float) -> tuple[float, float]:
        return (panel_x + x, y)

    hip = p(355 + 38 * ease, 315 + 140 * ease)
    shoulder = p(342 + 30 * ease, 178 + 118 * ease)
    neck = p(344 + 30 * ease, 148 + 118 * ease)
    head = p(346 + 30 * ease, 105 + 118 * ease + bounce)

    return {
        "head": head,
        "neck": neck,
        "shoulder": shoulder,
        "hip": hip,
        "front_knee": p(420 + 78 * ease, 476 + 58 * ease),
        "front_ankle": p(486, 632),
        "front_heel": p(440, 635),
        "front_toe": p(548, 637),
        "rear_knee": p(294 + 54 * ease, 498 + 100 * ease),
        "rear_ankle": p(246, 632),
        "rear_heel": p(214, 636),
        "rear_toe": p(312, 638),
        "elbow": p(405 + 20 * ease, 320 + 95 * ease),
        "wrist": p(445 + 14 * ease, 410 + 80 * ease),
    }


def draw_trainer_reference(canvas: Canvas, frame: int, panel_x: int = 0) -> None:
    pts = trainer_reference_points(frame, panel_x)
    canvas.line((panel_x + 145, 656), (panel_x + 610, 656), 2, (104, 153, 126), 0.55)
    canvas.circle(panel_x + 380, 658, 150, (255, 207, 92), 0.035)

    bone = (238, 255, 250)
    front = (255, 207, 92)
    rear = (126, 218, 236)
    torso = (139, 232, 221)
    for a, b, radius, color in [
        ("head", "neck", 6, bone),
        ("neck", "shoulder", 7, bone),
        ("shoulder", "hip", 13, torso),
        ("shoulder", "elbow", 7, bone),
        ("elbow", "wrist", 6, bone),
        ("hip", "front_knee", 9, front),
        ("front_knee", "front_ankle", 8, front),
        ("front_heel", "front_toe", 6, front),
        ("hip", "rear_knee", 8, rear),
        ("rear_knee", "rear_ankle", 7, rear),
        ("rear_heel", "rear_toe", 6, rear),
    ]:
        canvas.line(pts[a], pts[b], radius, color, 0.96)

    for name, radius, color in [
        ("head", 18, (255, 237, 71)),
        ("shoulder", 9, bone),
        ("hip", 10, bone),
        ("front_knee", 8, front),
        ("rear_knee", 8, rear),
        ("front_ankle", 7, bone),
        ("rear_ankle", 7, bone),
    ]:
        canvas.circle(*pts[name], radius, color, 1)


def read_rows(path: Path) -> list[list[float]]:
    rows: list[list[float]] = []
    with path.open() as f:
        for line in f:
            values = [float(x) for x in line.strip().split(",") if x.strip()]
            if values:
                rows.append(values)
    return rows


def mat_vec(m: list[list[float]], v: list[float]) -> list[float]:
    return [sum(m[i][j] * v[j] for j in range(3)) for i in range(3)]


def mat_mul(a: list[list[float]], b: list[list[float]]) -> list[list[float]]:
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def rotx(t: float) -> list[list[float]]:
    c, s = math.cos(t), math.sin(t)
    return [[1, 0, 0], [0, c, -s], [0, s, c]]


def roty(t: float) -> list[list[float]]:
    c, s = math.cos(t), math.sin(t)
    return [[c, 0, s], [0, 1, 0], [-s, 0, c]]


def rotz(t: float) -> list[list[float]]:
    c, s = math.cos(t), math.sin(t)
    return [[c, -s, 0], [s, c, 0], [0, 0, 1]]


def e2r(euler: list[float]) -> list[list[float]]:
    g, b, a = euler
    return mat_mul(mat_mul(rotz(a), roty(b)), rotx(g))


def add(a: list[float], b: list[float]) -> list[float]:
    return [a[i] + b[i] for i in range(3)]


def absolute_kinect_skeleton(position_row: list[float], angle_row: list[float]) -> list[list[float]]:
    joint_pos = [position_row[i * 3 : i * 3 + 3] for i in range(22)]
    joint_ang = [[math.radians(v) for v in angle_row[i * 3 : i * 3 + 3]] for i in range(22)]

    r1 = e2r(joint_ang[0])
    joint_pos[1] = add(mat_vec(r1, joint_pos[1]), joint_pos[0])
    r2 = mat_mul(r1, e2r(joint_ang[1]))
    joint_pos[2] = add(mat_vec(r2, joint_pos[2]), joint_pos[1])
    r3 = mat_mul(r2, e2r(joint_ang[2]))
    joint_pos[3] = add(mat_vec(r3, joint_pos[3]), joint_pos[2])
    r4 = mat_mul(r3, e2r(joint_ang[3]))
    joint_pos[4] = add(mat_vec(r4, joint_pos[4]), joint_pos[3])
    r5 = mat_mul(r4, e2r(joint_ang[4]))
    joint_pos[5] = add(mat_vec(r5, joint_pos[5]), joint_pos[4])

    r6 = e2r(joint_ang[2])
    joint_pos[6] = add(mat_vec(r6, joint_pos[6]), joint_pos[2])
    r7 = mat_mul(r6, e2r(joint_ang[6]))
    joint_pos[7] = add(mat_vec(r7, joint_pos[7]), joint_pos[6])
    r8 = mat_mul(r7, e2r(joint_ang[7]))
    joint_pos[8] = add(mat_vec(r8, joint_pos[8]), joint_pos[7])
    r9 = mat_mul(r8, e2r(joint_ang[8]))
    joint_pos[9] = add(mat_vec(r9, joint_pos[9]), joint_pos[8])

    r10 = e2r(joint_ang[2])
    joint_pos[10] = add(mat_vec(r10, joint_pos[10]), joint_pos[2])
    r11 = mat_mul(r10, e2r(joint_ang[10]))
    joint_pos[11] = add(mat_vec(r11, joint_pos[11]), joint_pos[10])
    r12 = mat_mul(r11, e2r(joint_ang[11]))
    joint_pos[12] = add(mat_vec(r12, joint_pos[12]), joint_pos[11])
    r13 = mat_mul(r12, e2r(joint_ang[12]))
    joint_pos[13] = add(mat_vec(r13, joint_pos[13]), joint_pos[12])

    r14 = e2r(joint_ang[0])
    joint_pos[14] = add(mat_vec(r14, joint_pos[14]), joint_pos[0])
    r15 = mat_mul(r14, e2r(joint_ang[14]))
    joint_pos[15] = add(mat_vec(r15, joint_pos[15]), joint_pos[14])
    r16 = mat_mul(r15, e2r(joint_ang[15]))
    joint_pos[16] = add(mat_vec(r16, joint_pos[16]), joint_pos[15])
    r17 = mat_mul(r16, e2r(joint_ang[16]))
    joint_pos[17] = add(mat_vec(r17, joint_pos[17]), joint_pos[16])

    r18 = e2r(joint_ang[0])
    joint_pos[18] = add(mat_vec(r18, joint_pos[18]), joint_pos[0])
    r19 = mat_mul(r18, e2r(joint_ang[18]))
    joint_pos[19] = add(mat_vec(r19, joint_pos[19]), joint_pos[18])
    r20 = mat_mul(r19, e2r(joint_ang[19]))
    joint_pos[20] = add(mat_vec(r20, joint_pos[20]), joint_pos[19])
    r21 = mat_mul(r20, e2r(joint_ang[20]))
    joint_pos[21] = add(mat_vec(r21, joint_pos[21]), joint_pos[20])
    return joint_pos


def ensure_ui_prmd_sample() -> Path:
    sample_dir = Path("/tmp/camifit-ui-prmd-sample")
    if not (sample_dir / "data" / "m03_s01_e01_positions.txt").exists():
        if sample_dir.exists():
            shutil.rmtree(sample_dir)
        subprocess.run(
            [
                "git",
                "clone",
                "--depth",
                "1",
                "https://github.com/tejas1904/UI-PRMD-Visualize-python-port.git",
                str(sample_dir),
            ],
            check=True,
        )
    return sample_dir


def load_ui_prmd_inline_lunge() -> list[list[list[float]]]:
    sample_dir = ensure_ui_prmd_sample()
    data_dir = sample_dir / "data"
    positions = read_rows(data_dir / "m03_s01_e01_positions.txt")
    angles = read_rows(data_dir / "m03_s01_e01_angles.txt")
    return [absolute_kinect_skeleton(p, a) for p, a in zip(positions, angles)]


UI_EDGES = [
    (0, 1), (1, 2), (2, 3), (3, 4), (4, 5),
    (2, 6), (6, 7), (7, 8), (8, 9),
    (2, 10), (10, 11), (11, 12), (12, 13),
    (0, 14), (14, 15), (15, 16), (16, 17),
    (0, 18), (18, 19), (19, 20), (20, 21),
]


def dataset_projector(skels: list[list[list[float]]], panel_x: int = 0):
    projected = []
    for skel in skels:
        frame_points = []
        for joint in skel:
            # Oblique projection: mostly Kinect x/y, with a little z for depth.
            frame_points.append((joint[0] + (joint[2] * 0.20), joint[1]))
        projected.append(frame_points)

    xs = [p[0] for frame in projected for p in frame]
    ys = [p[1] for frame in projected for p in frame]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    scale = min(470 / max(max_x - min_x, 1), 520 / max(max_y - min_y, 1))
    center_x = (min_x + max_x) / 2
    floor_y = 665

    def map_point(point: tuple[float, float]) -> tuple[float, float]:
        x, y = point
        return (
            panel_x + PANEL_W / 2 + (x - center_x) * scale,
            floor_y - (y - min_y) * scale,
        )

    return [[map_point(p) for p in frame] for frame in projected]


def draw_dataset(canvas: Canvas, projected: list[list[tuple[float, float]]], frame: int, panel_x: int = 0) -> None:
    pts = projected[frame % len(projected)]
    canvas.line((panel_x + 130, 675), (panel_x + 620, 675), 2, (118, 134, 166), 0.50)
    canvas.circle(panel_x + 380, 675, 155, (77, 137, 255), 0.032)

    for i, (a, b) in enumerate(UI_EDGES):
        if i >= 13:
            color = (255, 208, 98) if i < 17 else (132, 220, 238)
            radius = 6
        elif i >= 5:
            color = (226, 247, 255)
            radius = 5
        else:
            color = (155, 235, 222)
            radius = 7
        canvas.line(pts[a], pts[b], radius, color, 0.94)

    for idx in [0, 2, 4, 14, 15, 16, 18, 19, 20]:
        color = (255, 235, 91) if idx == 4 else (242, 253, 255)
        canvas.circle(*pts[idx], 7 if idx != 4 else 15, color, 1)


def render_frames(
    kind: str,
    dataset_points: list[list[tuple[float, float]]] | None = None,
    labels: list[tuple[str, int, int, int]] | None = None,
) -> Path:
    frames = FRAME_DIR / kind
    if frames.exists():
        shutil.rmtree(frames)
    frames.mkdir(parents=True)
    if kind == "side-by-side":
        background_canvas = Canvas(SIDE_W, SIDE_H)
    else:
        background_canvas = Canvas(PANEL_W, PANEL_H)
    background_canvas.fill_gradient((6, 25, 28), (17, 20, 35))
    background = background_canvas.pixels

    for frame in range(FRAME_COUNT):
        if kind == "side-by-side":
            canvas = Canvas(SIDE_W, SIDE_H, background)
            draw_trainer_reference(canvas, frame, 0)
            if dataset_points is None:
                raise RuntimeError("dataset points required")
            draw_dataset(canvas, dataset_points, frame, PANEL_W)
            canvas.line((PANEL_W, 0), (PANEL_W, PANEL_H), 2, (80, 104, 112), 0.55)
        else:
            canvas = Canvas(PANEL_W, PANEL_H, background)
            if kind == "reference":
                draw_trainer_reference(canvas, frame, 0)
            elif kind == "dataset":
                if dataset_points is None:
                    raise RuntimeError("dataset points required")
                draw_dataset(canvas, dataset_points, frame, 0)
            else:
                raise RuntimeError(f"unknown frame kind {kind}")
        for text, x, y, scale in labels or []:
            draw_label(canvas, text, x, y, scale)
        canvas.write_ppm(frames / f"frame_{frame:04d}.ppm")
    return frames


def encode_video(frames: Path, output: Path, width: int) -> None:
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-framerate",
            str(FPS),
            "-i",
            str(frames / "frame_%04d.ppm"),
            "-vf",
            "null",
            "-s",
            f"{width}x{PANEL_H}",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            str(output),
        ],
        check=True,
    )


def write_notes() -> None:
    notes = OUT_DIR / "README.md"
    notes.write_text(
        "\n".join(
            [
                "# Avatar Motion Source Comparison",
                "",
                "Generated by `scripts/render_avatar_motion_comparison.py`.",
                "",
                "Artifacts:",
                "",
                "- `reference-video-mediapipe-prototype.mp4`: target biomechanics for a future trainer-reference video trace. This is not imported from a real trainer clip yet.",
                "- `dataset-ui-prmd-inline-lunge.mp4`: actual UI-PRMD inline-lunge sample from the public visualization mirror, reconstructed from Kinect positions plus Euler angles.",
                "- `side-by-side-motion-data-comparison.mp4`: both lanes rendered together.",
                "",
                "Provenance:",
                "",
                "- Trainer lane: planned source path is trainer video -> existing CamiFit MediaPipe worker in VIDEO mode -> PoseFrame JSONL -> MotionDemoTimeline.",
                "- Dataset lane: sample files `m03_s01_e01_positions.txt` and `m03_s01_e01_angles.txt` cloned to `/tmp/camifit-ui-prmd-sample` from `https://github.com/tejas1904/UI-PRMD-Visualize-python-port.git`.",
                "- UI-PRMD official paper/page describe inline lunge as movement m03 and the data as Kinect/Vicon joint positions and angles.",
                "",
            ]
        ),
        encoding="utf-8",
    )


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    dataset = dataset_projector(load_ui_prmd_inline_lunge(), PANEL_W)
    dataset_single = [[(x - PANEL_W, y) for x, y in frame] for frame in dataset]

    reference_frames = render_frames(
        "reference",
        labels=[
            ("TRAINER VIDEO PATH", 32, 32, 4),
            ("PROTOTYPE TARGET MOTION", 32, 76, 3),
        ],
    )
    dataset_frames = render_frames(
        "dataset",
        dataset_single,
        labels=[
            ("UI PRMD DATASET", 32, 32, 4),
            ("REAL INLINE LUNGE SAMPLE", 32, 76, 3),
        ],
    )
    side_frames = render_frames(
        "side-by-side",
        dataset,
        labels=[
            ("A TRAINER VIDEO PATH", 32, 32, 3),
            ("PROTOTYPE TARGET MOTION", 32, 68, 2),
            ("B UI PRMD DATASET", PANEL_W + 32, 32, 3),
            ("REAL INLINE LUNGE SAMPLE", PANEL_W + 32, 68, 2),
        ],
    )

    encode_video(
        reference_frames,
        OUT_DIR / "reference-video-mediapipe-prototype.mp4",
        PANEL_W,
    )
    encode_video(
        dataset_frames,
        OUT_DIR / "dataset-ui-prmd-inline-lunge.mp4",
        PANEL_W,
    )
    encode_video(
        side_frames,
        OUT_DIR / "side-by-side-motion-data-comparison.mp4",
        SIDE_W,
    )
    write_notes()


if __name__ == "__main__":
    main()
