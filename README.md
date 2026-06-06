# CamiFit

An open-ended, **on-device** bodyweight-exercise coach for macOS. CamiFit watches you through the webcam, counts reps, checks your form against per-exercise rules, tracks sets, and gives live cues — all locally, offline.

The heart of CamiFit is a deterministic, timestamped **exercise engine** that runs an **Exercise-Program**: a JSON document with a small, sandboxed rule **DSL**. The same contract is hand-authored today and (later) authored dynamically by an agent — so adding a new exercise is data, not code.

```
PoseProvider (MediaPipe pose worker)  →  joint-angle signals  →  temporal filters
   →  validity gating  →  rep / hold / set state machines  →  form rules  →  cues + summary
```

## Layers

- **Layer 1 — On-device executor (current):** pose → signals → reps/form/sets, driven by hand-authored Exercise-Program JSON. Fully offline.
- **Layer 2 — Agent authoring (later):** a sidebar chat (Codex app-server + ChatGPT login) that generates new Exercise-Programs as validated JSON.
- **Layer 3 — Tracker (later):** saved routines, session history, progress over time.

## Status

Milestone **M1 — exercise engine + program contract (squat vertical)**. See:

- `docs/design/2026-06-03-camifit-exercise-engine-design.md` — full design.
- `GOAL.md` — active mission + constraints.
- `docs/briefs/` — current slice.

## Development

This repo uses a supervised **Codex executor / reviewer** workflow (see `executor-reviewer-pair-programming.md`):

```bash
scripts/run_codex_pair_cycle.sh --once     # one executor + reviewer cycle
scripts/audit_autonomous_workflow.sh       # check workflow state
```

The Swift engine builds with SwiftPM:

```bash
swift build
swift test
```

## Build And Run The Mac App

For Live Camera webcam tracking, set up the pose-worker dependency once after
cloning:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install mediapipe pytest

mkdir -p pose_worker/models
curl -L -o pose_worker/models/pose_landmarker_lite.task \
  https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task
```

Or run the bundled setup/diagnostic helper:

```bash
script/doctor_live_camera.sh --fix
script/doctor_live_camera.sh
```

The app first looks for `CAMIFIT_PYTHON`, then `.venv/bin/python`, then common
system Python 3 locations. On a fresh macOS install, do not set
`CAMIFIT_PYTHON=python`; use the local venv above or `CAMIFIT_PYTHON=python3`.
If Live Camera still fails, run `script/doctor_live_camera.sh` before opening
the app; it checks the exact Python command, Python version, MediaPipe import,
model file, and worker health response.

Use the project run script for the actual macOS app bundle. It builds the
SwiftPM executable, stages `dist/CamiFitApp.app`, signs it, and opens it as
**Future Coach**:

```bash
./script/build_and_run.sh --verify
```

To open the avatar guide on a specific exercise:

```bash
CAMIFIT_GUIDE_EXERCISE=bodyweight_squat ./script/build_and_run.sh --verify
```

Useful guide IDs right now:

```text
bodyweight_squat
bodyweight_lunge
bodyweight_pushup
bodyweight_plank
```

For visual debugging, pin the guide to a specific timeline position:

```bash
CAMIFIT_GUIDE_EXERCISE=bodyweight_squat \
CAMIFIT_GUIDE_FRAME_MS=1608 \
./script/build_and_run.sh --verify
```

## Lightweight Verification

On a slower MacBook Air, start with the focused gates instead of a full
monorepo pass:

```bash
swift test --disable-sandbox --filter MediaPipePoseProviderTests
scripts/motion_reference/audit_motion_coverage.py --strict
scripts/motion_reference/audit_kg_motion_readiness.py --summary-only
git diff --check
```

The full gate is heavier:

```bash
scripts/run_monorepo_gates.sh
```

If the machine is struggling, close the running app before rebuilding and avoid
rerendering motion-reference videos unless you are actively reviewing a trace.
Generated review media lives under `dist/`, which is intentionally ignored by
Git.

## Git Upload Checklist

Before pushing this branch, make sure these generated-but-important app assets
are tracked:

```bash
git status --short
git add Sources/CamiFitApp/Resources/MotionDemos \
        Sources/CamiFitApp/Resources/Avatars \
        scripts/motion_reference \
        script/build_and_run.sh \
        script/run_motion_reference_recorder.sh \
        Package.swift
```

Do not add `dist/`, `.build/`, MediaPipe `*.task` model files, or local webcam
captures. Those are ignored runtime/build artifacts.
