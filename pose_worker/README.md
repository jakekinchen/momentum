# CamiFit Pose Worker

A pure-Python, line-delimited (JSONL) stdin→stdout worker that turns camera
frames into MediaPipe pose landmarks for the CamiFit exercise engine. It is a
**pure pose source** — it holds no exercise/session state. The output JSON maps
directly onto `Sources/CamiFitEngine/PoseFrame.swift` (see the design doc §7/§8).

- 33 normalized image landmarks (`x, y, z, visibility, presence`)
- 33 metric 3D `world_landmarks` (`x, y, z`)
- `poses_detected` (0/1/2) and `primary_pose_id` (highest mean-visibility pose)
- MediaPipe Tasks `PoseLandmarker` in **VIDEO** running mode, `num_poses = 2`

## Layout

```
pose_worker/
├── pose_worker.py          # the JSONL worker
├── README.md
├── SESSION_LOG.md
├── models/                 # gitignored (models/, *.task)
│   ├── pose_landmarker_lite.task   # downloaded, not committed
│   └── test_assets/        # gitignored real-inference smoke images
└── tests/
    ├── conftest.py
    └── test_pose_worker.py
```

## Setup

The worker needs MediaPipe (which pulls in numpy / OpenCV) and, for tests,
pytest.

```bash
python3 -m venv .venv           # any Python 3.10+; 3.12 used here
source .venv/bin/activate
pip install mediapipe pytest
```

> For the macOS app, prefer a repo-local `.venv` at the project root. The app
> will automatically find `.venv/bin/python` when Live Camera starts.

### Download the model bundle

`models/` and `*.task` are gitignored, so the bundle is **never committed** and
must be downloaded once:

```bash
mkdir -p pose_worker/models
curl -L -o pose_worker/models/pose_landmarker_lite.task \
  https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task
```

(`pose_landmarker_full.task` / `pose_landmarker_heavy.task` also work; pass them
with `--model`.)

## Run the worker

```bash
# real inference
python3 pose_worker/pose_worker.py --mode mediapipe \
  --model pose_worker/models/pose_landmarker_lite.task

# deterministic synthetic landmarks (no camera, no model load)
python3 pose_worker/pose_worker.py --mode mock
python3 pose_worker/pose_worker.py --mode fixture
```

Send one JSON request per line on stdin; read one JSON response per line on
stdout.

### Requests

```json
{"type":"health"}
{"type":"predict","frame_id":123,"timestamp_ms":169000,"image_path":"frame.jpg"}
```

- `mock` / `fixture` modes ignore `image_path` and instead use a `"fixture"`
  field (`"standing"` default, or `"squat_bottom"`).
- In `mediapipe` mode `image_path` is required. Timestamps must be
  monotonically increasing for VIDEO mode; the worker enforces this by bumping
  any non-increasing timestamp by 1 ms.

### Responses

`health`:

```json
{"type":"health","ok":true,"pose_ready":true,"running_mode":"VIDEO",
 "num_poses":2,"model_path":"...","message":"mediapipe PoseLandmarker ready"}
```

In `mediapipe` mode `pose_ready` is `false` (with an install/download hint in
`message`) when MediaPipe or the model bundle is missing.

`pose` (one record per `predict`, for the primary pose):

```json
{"type":"pose","frame_id":123,"timestamp_ms":169000,"image_size":[1000,667],
 "poses_detected":1,"primary_pose_id":"0",
 "landmarks":[{"x":0.46,"y":0.42,"z":-0.15,"visibility":0.99,"presence":0.99}, "…33"],
 "world_landmarks":[{"x":-0.08,"y":-0.61,"z":-0.14}, "…33"],
 "latency_ms":18.9}
```

When no pose is detected: `poses_detected:0`, `primary_pose_id:null`, and both
landmark arrays empty.

Bad input never crashes the loop — it is reported as
`{"type":"error","error":"..."}` and the worker keeps reading.

### Example

```bash
printf '%s\n' \
  '{"type":"health"}' \
  '{"type":"predict","frame_id":1,"timestamp_ms":1000,"image_path":"pose_worker/models/test_assets/standing.jpg"}' \
  | python3 pose_worker/pose_worker.py --mode mediapipe
```

## Tests

```bash
source .venv/bin/activate
python -m pytest pose_worker/tests -q
```

Tests cover health readiness (mediapipe with/without the model bundle),
mock/fixture determinism, the full JSONL schema (exactly 33 landmarks each with
`x/y/z/visibility/presence`; 33 `world_landmarks`; all required top-level
fields), `poses_detected`/`primary_pose_id` logic, error handling, and a real
`mediapipe`-mode inference smoke on a person image (asserting
`poses_detected >= 1` with nonzero visibility/presence), plus a blank-frame
check (`poses_detected == 0`).

### Real-inference smoke asset

`tests/` downloads a person image to `pose_worker/models/test_assets/standing.jpg`
(a gitignored path, so it is never committed). In this workspace it was fetched
from the public Google MediaPipe assets bucket:

```bash
curl -L -o pose_worker/models/test_assets/standing.jpg \
  https://storage.googleapis.com/mediapipe-assets/pose.jpg
```

If that image is missing, the smoke test runs health-only and the suite still
relies on the blank-frame test to confirm the model loads and runs
(`poses_detected == 0`).
