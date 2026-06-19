#!/usr/bin/env python3
"""CamiFit MediaPipe pose worker.

A line-delimited (JSONL) stdin -> stdout request/response worker that acts as a
pure, timestamped pose source for the CamiFit exercise engine. It holds NO
exercise/session state.

Transport
---------
One JSON object per line on stdin; one JSON object per line on stdout.

Requests
--------
  {"type": "health"}
  {"type": "predict", "frame_id": <int>, "image_path": "<path>",
                      "timestamp_ms": <int>}

Responses
---------
  health  -> {"type": "health", "ok": true, "pose_ready": <bool>,
              "running_mode": "VIDEO", "num_poses": 2, "model_path": "...",
              "message": "..."}
  predict -> {"type": "pose", "frame_id": ..., "timestamp_ms": ...,
              "image_size": [w, h], "poses_detected": N,
              "primary_pose_id": "0" | null,
              "landmarks": [ 33 x {x, y, z, visibility, presence} ],
              "world_landmarks": [ 33 x {x, y, z} ],
              "latency_ms": ...}
  error   -> {"type": "error", "error": "..."}  (loop never crashes)

Modes
-----
  mediapipe : real inference using MediaPipe Tasks PoseLandmarker in VIDEO mode.
  mock      : deterministic synthetic landmarks (no camera, no model load).
  fixture   : deterministic recorded poses (standing / squat_bottom), selectable
              per-request via {"fixture": "standing"|"squat_bottom"}.

The PoseFrame JSON shape mirrors §7/§8 of the CamiFit engine design doc and
maps onto Sources/CamiFitEngine/PoseFrame.swift (x/y/z + visibility + presence
per normalized landmark; x/y/z per world landmark; both kept distinct).
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
import time
from typing import Any, Dict, List, Optional, Tuple

# MediaPipe's canonical 33 pose landmarks, in index order.
LANDMARK_NAMES: List[str] = [
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
NUM_LANDMARKS = len(LANDMARK_NAMES)  # 33

DEFAULT_MODEL_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "models", "pose_landmarker_lite.task"
)
DEFAULT_NUM_POSES = 2
DEFAULT_IMAGE_SIZE = (1280, 720)


# --------------------------------------------------------------------------- #
# Synthetic fixtures (mock / fixture modes)                                    #
# --------------------------------------------------------------------------- #
def _landmark(
    x: float, y: float, z: float, visibility: float, presence: float
) -> Dict[str, float]:
    return {
        "x": float(x),
        "y": float(y),
        "z": float(z),
        "visibility": float(visibility),
        "presence": float(presence),
    }


def _build_fixture_pose(knee_angle_deg: float, *, visibility: float = 0.95) -> Dict[str, Any]:
    """Build a deterministic, anatomically-plausible side-view pose.

    `knee_angle_deg` controls how bent the knee is: ~175 deg => standing tall,
    ~70 deg => squat bottom. Coordinates are normalized (0..1), y grows downward
    (MediaPipe convention). Both visibility and presence are populated.
    """
    # Vertical anchors for a person standing in frame (normalized, y down).
    head_y = 0.10
    shoulder_y = 0.25
    hip_y = 0.50
    ankle_y = 0.92
    cx = 0.50  # body centre x

    # Knee position is derived from the desired knee angle so squat lowers it.
    # Treat thigh (hip->knee) and shin (knee->ankle) as roughly equal segments.
    seg = (ankle_y - hip_y) / 2.0
    half = math.radians(knee_angle_deg) / 2.0
    # As the knee bends (smaller angle) the knee moves forward (x) and the hip
    # drops; approximate by lowering hip and pushing knee forward.
    knee_forward = (1.0 - math.sin(half)) * 0.12
    drop = (1.0 - math.sin(half)) * 0.10
    knee_y = hip_y + seg + drop
    knee_x = cx + knee_forward

    norm: List[Dict[str, float]] = []
    world: List[Dict[str, float]] = []

    def put(name: str, x: float, y: float, z: float = 0.0, vis: float = visibility) -> None:
        idx = LANDMARK_NAMES.index(name)
        # x/y/z normalized image landmarks + visibility/presence.
        norm_slots[idx] = _landmark(x, y, z, vis, min(1.0, vis + 0.02))
        # world landmarks: metres-ish, origin at hip midpoint, y up.
        world_slots[idx] = {
            "x": float((x - cx) * 1.5),
            "y": float((hip_y - y) * 1.8),
            "z": float(z),
        }

    # Pre-fill every slot so we always emit exactly 33 landmarks.
    norm_slots: List[Optional[Dict[str, float]]] = [None] * NUM_LANDMARKS
    world_slots: List[Optional[Dict[str, float]]] = [None] * NUM_LANDMARKS

    # Head cluster.
    for name in (
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
    ):
        put(name, cx, head_y, vis=visibility * 0.9)

    # Shoulders / arms.
    put("left_shoulder", cx - 0.08, shoulder_y)
    put("right_shoulder", cx + 0.08, shoulder_y)
    put("left_elbow", cx - 0.10, shoulder_y + 0.12)
    put("right_elbow", cx + 0.10, shoulder_y + 0.12)
    put("left_wrist", cx - 0.11, shoulder_y + 0.24)
    put("right_wrist", cx + 0.11, shoulder_y + 0.24)
    for name in ("left_pinky", "left_index", "left_thumb"):
        put(name, cx - 0.12, shoulder_y + 0.26, vis=visibility * 0.85)
    for name in ("right_pinky", "right_index", "right_thumb"):
        put(name, cx + 0.12, shoulder_y + 0.26, vis=visibility * 0.85)

    # Hips / legs (the part that moves with knee angle).
    put("left_hip", cx - 0.06, hip_y + drop)
    put("right_hip", cx + 0.06, hip_y + drop)
    put("left_knee", knee_x - 0.05, knee_y)
    put("right_knee", knee_x + 0.05, knee_y)
    put("left_ankle", cx - 0.05, ankle_y)
    put("right_ankle", cx + 0.05, ankle_y)
    put("left_heel", cx - 0.06, ankle_y + 0.02, vis=visibility * 0.9)
    put("right_heel", cx + 0.06, ankle_y + 0.02, vis=visibility * 0.9)
    put("left_foot_index", cx - 0.02, ankle_y + 0.03, vis=visibility * 0.9)
    put("right_foot_index", cx + 0.02, ankle_y + 0.03, vis=visibility * 0.9)

    # Any slot left unset (shouldn't happen) gets a low-visibility placeholder.
    for i in range(NUM_LANDMARKS):
        if norm_slots[i] is None:
            norm_slots[i] = _landmark(cx, 0.5, 0.0, 0.0, 0.0)
        if world_slots[i] is None:
            world_slots[i] = {"x": 0.0, "y": 0.0, "z": 0.0}

    norm = [s for s in norm_slots if s is not None]
    world = [s for s in world_slots if s is not None]
    return {"landmarks": norm, "world_landmarks": world}


# Named fixtures available to mock/fixture modes.
FIXTURES: Dict[str, Dict[str, Any]] = {
    "standing": _build_fixture_pose(175.0),
    "squat_bottom": _build_fixture_pose(70.0),
}


def mean_visibility(landmarks: List[Dict[str, float]]) -> float:
    if not landmarks:
        return 0.0
    return sum(l["visibility"] for l in landmarks) / len(landmarks)


def primary_pose_id(poses: List[List[Dict[str, float]]]) -> Optional[str]:
    """Index (as a string) of the highest mean-visibility pose, or None."""
    if not poses:
        return None
    best_idx = 0
    best_vis = -1.0
    for idx, lms in enumerate(poses):
        vis = mean_visibility(lms)
        if vis > best_vis:
            best_vis = vis
            best_idx = idx
    return str(best_idx)


def build_pose_response(
    *,
    frame_id: Any,
    timestamp_ms: Any,
    image_size: Tuple[int, int],
    pose_landmark_sets: List[List[Dict[str, float]]],
    pose_world_landmark_sets: List[List[Dict[str, float]]],
    latency_ms: float,
) -> Dict[str, Any]:
    """Assemble the JSONL `pose` record for the primary detected pose.

    `poses_detected` is the number of detected poses (0/1/2). The emitted
    landmark arrays belong to the primary (highest mean-visibility) pose; if no
    pose is detected, both arrays are empty and primary_pose_id is null.
    """
    poses_detected = len(pose_landmark_sets)
    primary = primary_pose_id(pose_landmark_sets)
    if primary is not None:
        pidx = int(primary)
        landmarks = pose_landmark_sets[pidx]
        world = (
            pose_world_landmark_sets[pidx]
            if pidx < len(pose_world_landmark_sets)
            else []
        )
    else:
        landmarks = []
        world = []
    return {
        "type": "pose",
        "frame_id": frame_id,
        "timestamp_ms": timestamp_ms,
        "image_size": [int(image_size[0]), int(image_size[1])],
        "poses_detected": poses_detected,
        "primary_pose_id": primary,
        "landmarks": landmarks,
        "world_landmarks": world,
        "latency_ms": round(float(latency_ms), 3),
    }


# --------------------------------------------------------------------------- #
# MediaPipe backend                                                            #
# --------------------------------------------------------------------------- #
def mediapipe_available() -> bool:
    try:
        import mediapipe  # noqa: F401
    except Exception:
        return False
    return True


class MediaPipeBackend:
    """Wraps a MediaPipe Tasks PoseLandmarker in VIDEO running mode."""

    def __init__(self, model_path: str, num_poses: int = DEFAULT_NUM_POSES):
        self.model_path = model_path
        self.num_poses = num_poses
        self.landmarker = None
        self._last_ts: int = -1
        self.error: Optional[str] = None
        self._init()

    def _init(self) -> None:
        if not mediapipe_available():
            self.error = (
                "mediapipe is not installed. Install it with "
                "`pip install mediapipe` in the worker venv."
            )
            return
        if not os.path.exists(self.model_path):
            self.error = (
                f"model bundle not found at {self.model_path}. Download it with: "
                "curl -L -o pose_worker/models/pose_landmarker_lite.task "
                "https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
                "pose_landmarker_lite/float16/latest/pose_landmarker_lite.task"
            )
            return
        try:
            from mediapipe.tasks.python.core.base_options import BaseOptions
            from mediapipe.tasks.python.vision.core.image import Image
            from mediapipe.tasks.python.vision.core.vision_task_running_mode import (
                VisionTaskRunningMode,
            )
            from mediapipe.tasks.python.vision.pose_landmarker import (
                PoseLandmarker,
                PoseLandmarkerOptions,
            )

            base_options = BaseOptions(model_asset_path=self.model_path)
            options = PoseLandmarkerOptions(
                base_options=base_options,
                running_mode=VisionTaskRunningMode.VIDEO,
                num_poses=self.num_poses,
            )
            self.landmarker = PoseLandmarker.create_from_options(options)
            self._mp_image = Image
        except Exception as exc:  # pragma: no cover - defensive
            self.error = f"failed to create PoseLandmarker: {exc}"

    @property
    def ready(self) -> bool:
        return self.landmarker is not None

    def detect(
        self, image_path: str, timestamp_ms: int
    ) -> Tuple[List[List[Dict[str, float]]], List[List[Dict[str, float]]], Tuple[int, int]]:
        if self.landmarker is None:
            raise RuntimeError(self.error or "PoseLandmarker not initialized")
        if not os.path.exists(image_path):
            raise FileNotFoundError(f"image_path not found: {image_path}")

        mp_image = self._mp_image.create_from_file(image_path)
        width, height = mp_image.width, mp_image.height

        # VIDEO mode requires monotonically increasing timestamps.
        ts = int(timestamp_ms)
        if ts <= self._last_ts:
            ts = self._last_ts + 1
        self._last_ts = ts

        result = self.landmarker.detect_for_video(mp_image, ts)

        norm_sets: List[List[Dict[str, float]]] = []
        for pose in result.pose_landmarks:
            norm_sets.append(
                [
                    _landmark(
                        lm.x,
                        lm.y,
                        lm.z,
                        lm.visibility if lm.visibility is not None else 0.0,
                        lm.presence if lm.presence is not None else 0.0,
                    )
                    for lm in pose
                ]
            )
        world_sets: List[List[Dict[str, float]]] = []
        for pose in result.pose_world_landmarks:
            world_sets.append(
                [{"x": float(lm.x), "y": float(lm.y), "z": float(lm.z)} for lm in pose]
            )
        return norm_sets, world_sets, (width, height)

    def close(self) -> None:
        if self.landmarker is not None:
            try:
                self.landmarker.close()
            except Exception:
                pass
            self.landmarker = None


# --------------------------------------------------------------------------- #
# Request handling                                                             #
# --------------------------------------------------------------------------- #
def handle_health(mode: str, model_path: str, backend: Optional[MediaPipeBackend]) -> Dict[str, Any]:
    if mode in ("mock", "fixture"):
        return {
            "type": "health",
            "ok": True,
            "pose_ready": True,
            "running_mode": "VIDEO",
            "num_poses": DEFAULT_NUM_POSES,
            "model_path": model_path,
            "message": f"{mode} mode ready (synthetic landmarks, no model load)",
        }

    # mediapipe mode
    ready = backend is not None and backend.ready
    if ready:
        message = "mediapipe PoseLandmarker ready"
    elif backend is not None and backend.error:
        message = backend.error
    elif not mediapipe_available():
        message = "mediapipe is not installed. Install it with `pip install mediapipe`."
    elif not os.path.exists(model_path):
        message = (
            f"model bundle not found at {model_path}. Download pose_landmarker_lite.task "
            "(see README)."
        )
    else:
        message = "mediapipe backend not ready"
    return {
        "type": "health",
        "ok": True,
        "pose_ready": bool(ready),
        "running_mode": "VIDEO",
        "num_poses": DEFAULT_NUM_POSES,
        "model_path": model_path,
        "message": message,
    }


def handle_predict(
    request: Dict[str, Any],
    mode: str,
    backend: Optional[MediaPipeBackend],
) -> Dict[str, Any]:
    frame_id = request.get("frame_id")
    timestamp_ms = request.get("timestamp_ms", 0)
    started = time.perf_counter()

    if mode in ("mock", "fixture"):
        fixture_name = request.get("fixture", "standing")
        if fixture_name not in FIXTURES:
            raise ValueError(
                f"unknown fixture '{fixture_name}'; available: {sorted(FIXTURES)}"
            )
        fixture = FIXTURES[fixture_name]
        # Deterministic: one pose, copied from the fixture.
        norm_sets = [list(fixture["landmarks"])]
        world_sets = [list(fixture["world_landmarks"])]
        image_size = tuple(request.get("image_size", DEFAULT_IMAGE_SIZE))
        latency_ms = (time.perf_counter() - started) * 1000.0
        return build_pose_response(
            frame_id=frame_id,
            timestamp_ms=timestamp_ms,
            image_size=image_size,
            pose_landmark_sets=norm_sets,
            pose_world_landmark_sets=world_sets,
            latency_ms=latency_ms,
        )

    # mediapipe mode
    if backend is None or not backend.ready:
        hint = backend.error if backend is not None else "mediapipe backend unavailable"
        raise RuntimeError(hint or "mediapipe backend unavailable")
    image_path = request.get("image_path")
    if not image_path:
        raise ValueError("predict request requires 'image_path' in mediapipe mode")
    norm_sets, world_sets, image_size = backend.detect(image_path, int(timestamp_ms))
    latency_ms = (time.perf_counter() - started) * 1000.0
    return build_pose_response(
        frame_id=frame_id,
        timestamp_ms=timestamp_ms,
        image_size=image_size,
        pose_landmark_sets=norm_sets,
        pose_world_landmark_sets=world_sets,
        latency_ms=latency_ms,
    )


def dispatch(
    request: Dict[str, Any],
    mode: str,
    model_path: str,
    backend: Optional[MediaPipeBackend],
) -> Dict[str, Any]:
    req_type = request.get("type")
    if req_type == "health":
        return handle_health(mode, model_path, backend)
    if req_type == "predict":
        return handle_predict(request, mode, backend)
    raise ValueError(f"unknown request type: {req_type!r}")


def run_loop(args: argparse.Namespace, stdin, stdout) -> int:
    backend: Optional[MediaPipeBackend] = None
    if args.mode == "mediapipe":
        # Construct the backend up front so health reflects readiness; it never
        # raises (errors are captured into backend.error).
        backend = MediaPipeBackend(args.model, num_poses=DEFAULT_NUM_POSES)

    try:
        for line in stdin:
            line = line.strip()
            if not line:
                continue
            try:
                request = json.loads(line)
            except json.JSONDecodeError as exc:
                _emit(stdout, {"type": "error", "error": f"invalid JSON: {exc}"})
                continue
            try:
                response = dispatch(request, args.mode, args.model, backend)
            except Exception as exc:  # noqa: BLE001 - report, never crash the loop
                response = {"type": "error", "error": str(exc)}
            _emit(stdout, response)
    finally:
        if backend is not None:
            backend.close()
    return 0


def _emit(stdout, obj: Dict[str, Any]) -> None:
    stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    stdout.flush()


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="CamiFit MediaPipe pose worker")
    parser.add_argument(
        "--mode",
        choices=["mock", "fixture", "mediapipe"],
        default="mediapipe",
        help="pose source backend (default: mediapipe)",
    )
    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL_PATH,
        help="path to pose_landmarker_lite.task (mediapipe mode)",
    )
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    args = build_arg_parser().parse_args(argv)
    return run_loop(args, sys.stdin, sys.stdout)


if __name__ == "__main__":
    raise SystemExit(main())
