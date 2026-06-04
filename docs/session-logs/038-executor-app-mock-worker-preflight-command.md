# 038 Executor - App Mock Worker Preflight Command

## Slice

Added a deterministic app-side mock-worker preflight command. The command verifies the configured repo-local worker path and reaches mock-worker health through the existing subprocess provider boundary without mutating the last run summary, HUD, overlay, or provider run status.

## Files Changed

- `Sources/CamiFitApp/AppMockWorkerPreflightStatus.swift`
  - Added `AppMockWorkerPreflightStatus` with `idle`, `checking`, `succeeded`, and `failed` states.
  - Added success/failure payloads with worker URL, command, health mode/message, and deterministic diagnostics.
- `Sources/CamiFitApp/AppExerciseSessionViewModel.swift`
  - Added published `mockWorkerPreflightStatus`, initialized to `.idle`.
  - Added `preflightMockWorker(workerScriptURL:)`.
  - Checks worker path existence before launch.
  - Calls `PoseWorkerSubprocessProvider.health()` for mock-worker health.
- `Sources/CamiFitApp/ContentView.swift`
  - Added compact preflight status text.
  - Added `Check Mock Worker` button beside existing provider controls.
- `Tests/CamiFitAppTests/AppMockWorkerPreflightTests.swift`
  - Added success and missing-path failure tests.
  - Proves preflight does not mutate last run summary, HUD, overlay, or provider run status.

## Validation

Focused:

```sh
swift test --disable-sandbox --filter AppMockWorkerPreflightTests
```

Result: passed, 2 tests, 0 failures.

Evidence:

```text
app-mock-worker-preflight-missing path=/Users/kelly/Developer/camifit/pose_worker/missing_pose_worker.py diagnostic=mock worker script not found: /Users/kelly/Developer/camifit/pose_worker/missing_pose_worker.py summary_mutated=false
app-mock-worker-preflight-success command=/usr/bin/env python3 /Users/kelly/Developer/camifit/pose_worker/pose_worker.py --mode mock mode=VIDEO message=mock mode ready (synthetic landmarks, no model load) summary_mutated=false
```

Broad:

```sh
swift build --disable-sandbox
swift test --disable-sandbox
scripts/audit_autonomous_workflow.sh
git diff --check -- Sources/CamiFitApp/AppMockWorkerPreflightStatus.swift Sources/CamiFitApp/AppExerciseSessionViewModel.swift Sources/CamiFitApp/ContentView.swift Tests/CamiFitAppTests/AppMockWorkerPreflightTests.swift
```

Results:

- `swift build --disable-sandbox`: passed.
- `swift test --disable-sandbox`: passed, 113 tests, 0 failures.
- `scripts/audit_autonomous_workflow.sh`: workflow audit clean.
- `git diff --check`: passed.

## Reachability

Success path proven by `testMockWorkerPreflightSuccessReachesWorkerHealthWithoutMutatingRunState`:

```text
ContentView "Check Mock Worker" button
-> AppExerciseSessionViewModel.preflightMockWorker(...)
-> worker path existence check
-> PoseWorkerSubprocessProvider.health()
-> /usr/bin/env python3 pose_worker/pose_worker.py --mode mock
-> AppMockWorkerPreflightStatus.succeeded(command, runningMode=VIDEO, message)
```

Missing-path failure proven by `testMockWorkerPreflightMissingPathFailsWithoutMutatingRunState`:

```text
preflightMockWorker(missing path)
-> path existence check
-> AppMockWorkerPreflightStatus.failed("mock worker script not found: ...")
```

Both tests assert no mutation of:

- `lastPoseProviderRunSummary`
- `latestHUDState`
- `latestPoseOverlayState`
- `poseProviderRunStatus`

## Boundary Statement

No live app launch, screenshot, camera run, `pose_worker/` change, pytest run, MediaPipe model download, or `pip install` occurred. This slice only adds headless app command wiring and tests for mock-worker preflight.

## Flags For Reviewer

- `PoseWorkerSubprocessProvider.health()` currently uses the existing provider subprocess boundary; no new Python protocol or worker code was added.
- Preflight status is separate from provider run status so a health check does not look like an exercise run.
- `ContentView` changes are compile-checked only; no visual verification claim is made.

## Next Suggested Slice

Prepare a reviewer/manager handoff for human-run SwiftUI verification of the app shell controls, or add one final deterministic status/preflight regression around preserving existing run status after a preflight check following a completed run.
