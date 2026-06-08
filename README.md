# Momentum - Your Future Coach

Momentum is an on-device macOS fitness coach for movement feedback, workout
planning, and training context.

- Live site: https://momentum-future.vercel.app
- Mac download: https://momentum-future.vercel.app/download
- Latest release: https://github.com/jakekinchen/momentum/releases/latest
- Stable DMG: https://github.com/jakekinchen/momentum/releases/latest/download/Momentum-macOS.dmg

Momentum watches movement locally through the Mac camera, counts reps and hold
time, checks form rules, guides supported exercises with motion demos, and uses
deterministic graph logic to explain why a workout was selected, filtered, or
substituted. The public product name is **Momentum - Your Future Coach**.

## Current Release

Validated release state as of 2026-06-08:

- App bundle: `Momentum.app`
- Public display name: `Momentum - Your Future Coach`
- Distribution: signed, notarized, stapled drag-to-Applications DMG
- Signing: `Developer ID Application: Jake Kinchen (BN58T9KR6C)`
- Current release tag: `macos-20260608-4`
- DMG SHA-256:
  `aa7dee5b3582a81a672c3714f16ab34d9647e6a0f12fbad6dd6965c8083e926a`

Open the DMG on a Mac, then drag Momentum into Applications. The app is a free
direct download outside the Mac App Store.

## What Momentum Does

- Tracks bodyweight movement locally through the webcam.
- Counts reps, holds, sets, tempo, and simple form signals.
- Supports runnable movement demos for squat, lunge, pushup, and plank.
- Builds workout plans from goals, schedule, equipment, safety constraints, and
  training context.
- Shows reason codes, graph paths, filtered candidates, and alternatives so the
  user can see why a recommendation belongs in the session.
- Keeps current camera tracking and safety decisions local and deterministic.

All assessment/member data in this repo is synthetic. The product does not
store real member health data or PHI.

## Product Boundaries

Momentum is currently a direct-download macOS release candidate, not an App
Store build. The workout planning and movement feedback paths are implemented,
but generated exercise recommendations are still split into:

- **motion-ready exercises:** runnable in the app with measurement or guide
  support.
- **recommendation-only exercises:** valid planning candidates that still need
  reviewed motion profiles before live execution.

The coach layer may summarize bounded receipts and graph-backed facts, but it
does not decide workout safety or invent member facts.

## Build The Mac App

From the repo root:

```bash
swift build
swift test
```

For live camera tracking, install the local pose-worker dependency once:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install mediapipe pytest

mkdir -p pose_worker/models
curl -L -o pose_worker/models/pose_landmarker_lite.task \
  https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task
```

Then build, sign, open, and verify the local app:

```bash
./script/build_and_run.sh --verify
```

Build a release bundle without launching it:

```bash
./script/build_and_run.sh release
```

## Verification

Focused checks:

```bash
(cd kg-canonical && uv run python -m pytest)
swift test --disable-sandbox --filter AssignmentWorkoutPlannerTests
swift test --disable-sandbox --filter RoutineCompilerTests
scripts/motion_reference/audit_motion_coverage.py --strict
scripts/motion_reference/audit_kg_motion_readiness.py --summary-only
git diff --check
```

Full closeout gate:

```bash
scripts/run_monorepo_gates.sh
```

The full gate runs Python graph tests, generated-artifact checks, Swift
conformance parity, full Swift tests, motion-reference coverage, motion
readiness, and current contract listing.

## Git Hygiene

Before pushing, review the worktree explicitly:

```bash
git status --short --branch
git diff --check
```

Do not add `dist/`, `.build/`, MediaPipe `*.task` model files, or local webcam
captures. Those are local runtime/build artifacts.
