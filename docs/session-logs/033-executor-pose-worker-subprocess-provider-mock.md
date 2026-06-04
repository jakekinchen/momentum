# 033 Executor - Pose Worker Subprocess Provider Mock

## Slice

Implemented the smallest useful Swift-side subprocess boundary for the existing `pose_worker/pose_worker.py --mode mock` contract. The provider performs a JSONL `health` request and a deterministic mock `predict` request over stdin/stdout, decodes the returned pose into `PoseFrame`, and exposes both the engine `PoseProvider` path and app session command path without adding checked-in JSONL fixtures.

## Files Changed

- `Sources/CamiFitEngine/PoseWorkerSubprocessProvider.swift`
  - Added `PoseWorkerSubprocessProvider`, `PoseWorkerHealth`, and deterministic `PoseWorkerSubprocessError` cases.
  - Default command is `/usr/bin/env python3 <repo>/pose_worker/pose_worker.py --mode mock`.
  - `health()` launches the worker, sends `{"type":"health"}`, validates the response, and returns structured health evidence.
  - `frames()` launches the worker, sends `health` plus one `predict` request, validates health, and decodes the returned JSONL pose through `MediaPipePoseJSONLDecoder`.
- `Sources/CamiFitEngine/MediaPipePoseProvider.swift`
  - Accepted both string and integer `primary_pose_id` values so Swift remains compatible with the Python subprocess response contract and existing integer fixture corpus.
- `Tests/CamiFitAppTests/PoseWorkerSubprocessProviderTests.swift`
  - Added focused subprocess health/predict decoding coverage.
  - Added app session command reachability coverage through `AppExerciseSessionViewModel.runRecordedProvider`.
  - Added deterministic missing-worker failure coverage before launch.

## Validation

Focused:

```sh
swift test --disable-sandbox --filter PoseWorkerSubprocessProviderTests
```

Result: passed, 3 tests, 0 failures.

Evidence:

```text
pose-worker-mock-missing-path error=pose worker script not found
pose-worker-mock-health command=/usr/bin/env python3 /Users/kelly/Developer/camifit/pose_worker/pose_worker.py --mode mock ok=true pose_ready=true mode=VIDEO message=mock mode ready (synthetic landmarks, no model load)
pose-worker-mock-frame frame_id=42 timestamp=1234 size=1280.0x720.0 landmarks=37 primary_knee=Optional(CamiFitEngine.PoseLandmark(x: 0.5501142134101771, y: 0.7100951778418142, z: 0.0, visibility: 0.95, presence: 0.97))
pose-worker-mock-app-path selected=bodyweight_squat frames=1 reps=0 overlay_points=37 diagnostic=nil
```

Broad:

```sh
swift build --disable-sandbox
swift test --disable-sandbox
scripts/audit_autonomous_workflow.sh
git diff --check -- Sources/CamiFitEngine/PoseWorkerSubprocessProvider.swift Sources/CamiFitEngine/MediaPipePoseProvider.swift Tests/CamiFitAppTests/PoseWorkerSubprocessProviderTests.swift
```

Results:

- `swift build --disable-sandbox`: passed.
- `swift test --disable-sandbox`: passed, 98 tests, 0 failures.
- `scripts/audit_autonomous_workflow.sh`: workflow audit clean.
- `git diff --check`: passed.

Not run:

- `pytest` was not run because this slice did not modify `pose_worker/` and the current `GOAL.md` says the loop should not block on pytest for non-worker slices.
- No SwiftUI app launch, live camera, or on-screen overlay verification was attempted because those require human run-verification per `GOAL.md`.

## Reachability

Real product-path reachability proven by `testMockWorkerPoseFrameFeedsAppSessionCommandPath`:

```text
/usr/bin/env python3 pose_worker/pose_worker.py --mode mock
-> JSONL stdin health/predict
-> JSONL stdout health/pose
-> PoseWorkerSubprocessProvider.frames()
-> MediaPipePoseJSONLDecoder
-> PoseFrame
-> AppExerciseSessionViewModel.runRecordedProvider(...)
-> AppPoseProviderSession
-> app summary + overlay state
```

Test evidence:

```text
pose-worker-mock-app-path selected=bodyweight_squat frames=1 reps=0 overlay_points=37 diagnostic=nil
```

## Flags For Reviewer

- This is intentionally mock mode only; no `mediapipe` mode was wired or claimed.
- No live camera path was implemented.
- No model download, `pip install`, or Python environment mutation was performed.
- No `pose_worker/` source files were changed.
- The subprocess provider currently performs one deterministic mock `predict` per `frames()` call; streaming/live frame feeding is a later slice.
- The provider uses `Process` plus stdin/stdout JSONL and waits synchronously, which is enough for this offline mock product-path slice but not the final live camera loop.

## Next Suggested Slice

Wire an app-level injectable default pose provider factory that can select the subprocess mock provider behind a test-only or explicit launch configuration, still without live camera or MediaPipe model downloads.
