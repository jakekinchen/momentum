# 035 Executor - App Mock Worker UI Command

## Slice

Added a minimal app-shell command for deterministic mock-worker mode. The new command builds `AppPoseProviderMode.mockWorker(...)`, routes through `runConfiguredPoseProvider(...)`, and is exposed in `ContentView` as a small `Run Mock Worker` button. This remains a headlessly tested command boundary, not a live SwiftUI app verification claim.

## Files Changed

- `Sources/CamiFitApp/AppExerciseSessionViewModel.swift`
  - Added `runMockWorkerProvider(...)`, with injectable worker script URL, preset ID, fixture, frame ID, and timestamp.
  - Added `defaultMockWorkerScriptURL(currentDirectory:)`, resolving repo-local `pose_worker/pose_worker.py`.
  - The command delegates through `runConfiguredPoseProvider(mode: .mockWorker(...))`.
- `Sources/CamiFitApp/ContentView.swift`
  - Added one explicit `Run Mock Worker` button beside the existing recorded-run controls.
  - Recorded-run picker and `Run` button behavior remain unchanged.
- `Tests/CamiFitAppTests/AppMockWorkerCommandTests.swift`
  - Added focused command tests for success, deterministic missing-worker failure, and repo-local default URL construction.

## Command / Control Design

The command path is intentionally thin:

```text
ContentView "Run Mock Worker" button
-> AppExerciseSessionViewModel.runMockWorkerProvider()
-> AppPoseProviderMode.mockWorker(AppMockWorkerPoseProviderConfiguration)
-> runConfiguredPoseProvider(...)
-> AppPoseProviderFactory
-> PoseWorkerSubprocessProvider
-> existing app session/HUD/overlay path
```

The default command resolves `pose_worker/pose_worker.py` from `FileManager.default.currentDirectoryPath`. Tests inject the package-root URL directly so the command is deterministic under SwiftPM.

## Validation

Focused:

```sh
swift test --disable-sandbox --filter AppMockWorkerCommandTests
```

Result: passed, 3 tests, 0 failures.

Evidence:

```text
app-mock-worker-command-default-url path=/Users/kelly/Developer/camifit/pose_worker/pose_worker.py
app-mock-worker-command selected=bodyweight_squat frames=1 hud_frames=1 overlay_points=37 diagnostic=nil
app-mock-worker-command-missing selected=bodyweight_squat frames=0 hud_frames=0 diagnostic=Pose provider failed: pose worker script not found: /Users/kelly/Developer/camifit/pose_worker/missing_pose_worker.py
```

Broad:

```sh
swift build --disable-sandbox
swift test --disable-sandbox
scripts/audit_autonomous_workflow.sh
git diff --check -- Sources/CamiFitApp/AppExerciseSessionViewModel.swift Sources/CamiFitApp/ContentView.swift Tests/CamiFitAppTests/AppMockWorkerCommandTests.swift
```

Results:

- `swift build --disable-sandbox`: passed.
- `swift test --disable-sandbox`: passed, 105 tests, 0 failures.
- `scripts/audit_autonomous_workflow.sh`: workflow audit clean.
- `git diff --check`: passed.

Not run:

- `pytest` was not run because this slice did not modify `pose_worker/`.
- No SwiftUI app launch, screenshot, live camera, or visual verification was performed.

## Reachability

Mock-worker command reachability proven by `testMockWorkerCommandFeedsSummaryHUDAndOverlayState`:

```text
AppExerciseSessionViewModel.runMockWorkerProvider(...)
-> AppPoseProviderMode.mockWorker(...)
-> runConfiguredPoseProvider(...)
-> AppPoseProviderFactory.configuredProvider(for:)
-> PoseWorkerSubprocessProvider
-> /usr/bin/env python3 pose_worker/pose_worker.py --mode mock
-> JSONL health/predict
-> MediaPipePoseJSONLDecoder
-> PoseFrame
-> AppPoseProviderSession
-> AppPoseProviderRunSummary + AppHUDState + AppPoseOverlayState
```

UI reachability is compile-checked through `ContentView`:

```text
ContentView "Run Mock Worker" button -> viewModel.runMockWorkerProvider()
```

## Flags For Reviewer

- This is a minimal command/control slice only; no UI redesign was attempted.
- Mock worker mode only; no `mediapipe` worker mode was wired or claimed.
- No live camera capture path was implemented.
- No model download, `pip install`, or Python environment mutation was performed.
- No `pose_worker.py` source files were changed.
- No SwiftUI app launch, screenshot, or visual verification was performed.

## Next Suggested Slice

Add a deterministic app-side provider status model for the mock-worker command so the UI can distinguish idle/running/succeeded/failed states without introducing streaming or live-camera behavior.
