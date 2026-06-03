# Pose Worker — Session Log

- **Date:** 2026-06-03
- **Branch / worktree:** `pose-worker` @ `/Users/kelly/Developer/camifit-pose`
- **Scope:** Build the Python MediaPipe pose worker entirely under `pose_worker/`.
  No files outside `pose_worker/` were touched (engine track stays isolated).
- **Interpreter:** `/Users/kelly/Developer/camifit-pose-venv/bin/python`
  (Python 3.12.12, mediapipe 0.10.35, cv2 4.13.0, numpy 2.4.6, PIL 12.2.0).

## Files created

- `pose_worker/pose_worker.py` — JSONL stdin→stdout worker. Modes:
  `mediapipe` (VIDEO running mode, `num_poses=2`, `detect_for_video` with
  monotonic timestamps), `mock`, `fixture`. Preserves both `visibility` and
  `presence` per landmark and both normalized + 3D `world_landmarks`.
  `primary_pose_id` = index of highest mean-visibility pose (or null).
  Errors emitted as `{"type":"error",...}`; loop never crashes.
- `pose_worker/tests/conftest.py` — path setup + `run_worker()` subprocess helper.
- `pose_worker/tests/test_pose_worker.py` — 16 tests (see results below).
- `pose_worker/README.md` — setup, model download, run + test instructions.
- `pose_worker/SESSION_LOG.md` — this file.
- `pose_worker/models/pose_landmarker_lite.task` — pre-supplied, **gitignored**
  (`models/`, `*.task`), not committed.
- `pose_worker/models/test_assets/standing.jpg` — real-inference smoke image,
  **gitignored** (under `models/`), not committed.

## Environment prep (commands)

```
# pip was absent from the venv; bootstrapped it (mediapipe NOT reinstalled):
/Users/kelly/Developer/camifit-pose-venv/bin/python -m ensurepip --upgrade
/Users/kelly/Developer/camifit-pose-venv/bin/python -m pip install pytest
#   -> pytest 9.0.3
```

## Smoke image download

Wikimedia Commons thumbnails returned HTTP errors from this environment
("Wikimedia Error / Use thumbnail sizes listed on https://w.wiki/GHai"), so
several `upload.wikimedia.org` URLs failed (returned 2 KB HTML, not JPEG).
Fell back to the public Google MediaPipe assets bucket, which served a real
1000x667 JPEG of a standing person:

```
curl -L -o pose_worker/models/test_assets/standing.jpg \
  https://storage.googleapis.com/mediapipe-assets/pose.jpg
# -> JPEG image data, 1000x667, 44100 bytes
```

This satisfies the "real person image" path; the blank-frame fallback test is
also present and asserts `poses_detected == 0`.

## Validation

### pytest

```
/Users/kelly/Developer/camifit-pose-venv/bin/python -m pytest pose_worker/tests -q
................                                                         [100%]
16 passed in 3.03s
```

### Real `mediapipe`-mode predict (end-to-end)

```
printf '%s\n' \
  '{"type":"health"}' \
  '{"type":"predict","frame_id":1,"timestamp_ms":1000,"image_path":"pose_worker/models/test_assets/standing.jpg"}' \
  | /Users/kelly/Developer/camifit-pose-venv/bin/python pose_worker/pose_worker.py --mode mediapipe
```

Result:

```
HEALTH: ok=True pose_ready=True running_mode=VIDEO num_poses=2
        message="mediapipe PoseLandmarker ready"
POSE:   poses_detected=1  primary_pose_id="0"
        n_landmarks=33  n_world_landmarks=33  image_size=[1000, 667]
        latency_ms≈19

sample landmark[12] (left_shoulder):
  {"x": 0.4549674689769745, "y": 0.49071168899536133, "z": 0.063890241086483,
   "visibility": 0.9999918937683105, "presence": 0.9999934434890747}
sample world_landmark[12]:
  {"x": -0.1407032161951065, "y": -0.4802762567996979, "z": 0.031815141439437866}
```

`poses_detected == 1`, all 33 landmarks present, visibility AND presence nonzero
(~0.99999) — the real-inference smoke passes.

### Mock/fixture spot check

`--mode mock`/`fixture` emit deterministic 33-landmark standing and
squat_bottom poses with no model load; bad JSON and unknown request types are
reported as `error` records without crashing the loop.

## Notes / decisions

- The Swift `PoseFrame` struct currently stores `landmarks` as a
  `[String: PoseLandmark]` dictionary, while the design doc §7/§8 and this
  brief specify ordered arrays. Per the brief, the worker emits the
  **array** shape from the design doc (33 landmarks + 33 world landmarks,
  visibility+presence kept distinct). Mapping array↔dictionary is the Swift
  provider adapter's job and lives in the engine track.
- VIDEO mode requires strictly increasing timestamps; the worker bumps any
  non-increasing `timestamp_ms` by 1 ms to stay valid across replays.
