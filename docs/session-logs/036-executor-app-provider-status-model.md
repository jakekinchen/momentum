# 036 Executor - App Provider Status Model

## Slice

Added a deterministic app-side pose-provider run status model so the app can distinguish idle, running, succeeded, and failed outcomes for recorded-run and mock-worker commands. The implementation keeps command execution synchronous and does not add streaming, cancellation, timers, or live-camera behavior.

## Files Changed

- `Sources/CamiFitApp/AppPoseProviderRunStatus.swift`
  - Added `AppPoseProviderRunDescriptor` with deterministic `mode` and `source`.
  - Added success and failure payload structs.
  - Added `AppPoseProviderRunStatus` with `idle`, `running`, `succeeded`, and `failed` states plus display text.
- `Sources/CamiFitApp/AppExerciseSessionViewModel.swift`
  - Added published `poseProviderRunStatus`, initialized to `.idle`.
  - Wired recorded-run, configured-provider, and mock-worker command paths through status descriptors.
  - Preserves existing summary, HUD, overlay, preset, and recorded-run behavior.
- `Sources/CamiFitApp/ContentView.swift`
  - Added one compact status text line using `viewModel.poseProviderRunStatus.displayText`.
- `Tests/CamiFitAppTests/AppPoseProviderRunStatusTests.swift`
  - Added focused tests for idle, recorded-run success, mock-worker success, and missing mock-worker failure.

## Status Design

The status model is intentionally app-facing and deterministic:

```text
idle
running(mode/source)
succeeded(mode/source/frame_count)
failed(mode/source/diagnostic_text)
```

Command reachability:

```text
runRecordedRun(...)
-> running(recorded-run, recorded:<id>)
-> existing provider/session/HUD/overlay path
-> succeeded or failed
```

```text
runMockWorkerProvider(...)
-> runConfiguredPoseProvider(.mockWorker(...))
-> running(mock-worker, mock-worker:<launch command>)
-> AppPoseProviderFactory
-> PoseWorkerSubprocessProvider
-> existing provider/session/HUD/overlay path
-> succeeded or failed
```

## Validation

Focused:

```sh
swift test --disable-sandbox --filter AppPoseProviderRunStatusTests
```

Result: passed, 4 tests, 0 failures.

Evidence:

```text
app-provider-status-initial status=Provider idle
app-provider-status-missing-mock mode=mock-worker source=mock-worker:/usr/bin/env python3 /Users/kelly/Developer/camifit/pose_worker/missing_pose_worker.py --mode mock diagnostic=Pose provider failed: pose worker script not found: /Users/kelly/Developer/camifit/pose_worker/missing_pose_worker.py
app-provider-status-mock mode=mock-worker source=mock-worker:/usr/bin/env python3 /Users/kelly/Developer/camifit/pose_worker/pose_worker.py --mode mock frames=1 overlay_points=37
app-provider-status-recorded mode=recorded-run source=recorded:squat_two_frames frames=2
```

Broad:

```sh
swift build --disable-sandbox
swift test --disable-sandbox
scripts/audit_autonomous_workflow.sh
git diff --check -- Sources/CamiFitApp/AppPoseProviderRunStatus.swift Sources/CamiFitApp/AppExerciseSessionViewModel.swift Sources/CamiFitApp/ContentView.swift Tests/CamiFitAppTests/AppPoseProviderRunStatusTests.swift
```

Results:

- `swift build --disable-sandbox`: passed.
- `swift test --disable-sandbox`: passed, 109 tests, 0 failures.
- `scripts/audit_autonomous_workflow.sh`: workflow audit clean.
- `git diff --check`: passed.

## Reachability

Recorded-run status reachability is proven by `testRecordedRunSuccessUpdatesStatusWithSourceAndFrameCount`:

```text
AppExerciseSessionViewModel.runRecordedRun(id: "squat_two_frames")
-> MediaPipePoseProvider
-> AppPoseProviderSession
-> AppPoseProviderRunSummary
-> AppHUDState
-> AppPoseProviderRunStatus.succeeded(recorded-run, recorded:squat_two_frames, frame_count=2)
```

Mock-worker status reachability is proven by `testMockWorkerSuccessUpdatesStatusWithSourceAndFrameCount`:

```text
AppExerciseSessionViewModel.runMockWorkerProvider(...)
-> AppPoseProviderMode.mockWorker(...)
-> AppPoseProviderFactory
-> PoseWorkerSubprocessProvider
-> pose_worker.py --mode mock
-> AppPoseProviderSession
-> AppPoseProviderRunSummary + AppPoseOverlayState
-> AppPoseProviderRunStatus.succeeded(mock-worker, frame_count=1)
```

Missing mock-worker failure reachability is proven by `testMissingMockWorkerUpdatesFailedStatusWithDeterministicDiagnostic`.

## Boundary Statement

No live app launch, screenshot, camera run, `pose_worker/` change, pytest run, MediaPipe model download, or `pip install` occurred. This slice is a synchronous app-side status model only.

## Flags For Reviewer

- `running` is a synchronous transition set before command execution; this slice does not add async observation or cancellation.
- `ContentView` status display is compile-checked only; no SwiftUI app-run or visual verification claim is made.
- Existing recorded-run catalog, HUD, overlay, and provider factory tests remain green.

## Next Suggested Slice

Add deterministic status coverage for direct provider failures from `runRecordedProvider(...)`, or begin a minimal app-side preflight for mock-worker availability before moving toward human-run SwiftUI verification.
