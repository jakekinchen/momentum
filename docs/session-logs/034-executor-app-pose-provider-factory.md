# 034 Executor - App Pose Provider Factory

## Slice

Added an app-layer pose provider configuration/factory boundary so the app command path can explicitly select either the existing safe recorded-run catalog mode or the deterministic mock subprocess worker from brief 033. This stays headless and does not enable live camera, MediaPipe worker mode, downloads, or SwiftUI app-run verification.

## Files Changed

- `Sources/CamiFitApp/AppPoseProviderFactory.swift`
  - Added `AppPoseProviderMode` with `.recordedRun(id:)` and `.mockWorker(...)`.
  - Added `AppMockWorkerPoseProviderConfiguration` for mock worker script URL, preset ID, fixture, frame ID, timestamp, and image size.
  - Added `AppPoseProviderFactory.configuredProvider(for:)`, returning a provider plus preset-routing metadata.
  - Recorded mode resolves `AppRecordedRunCatalog` and returns `MediaPipePoseProvider`.
  - Mock mode returns `PoseWorkerSubprocessProvider` pinned to the existing mock-worker boundary.
- `Sources/CamiFitApp/AppExerciseSessionViewModel.swift`
  - Added `runConfiguredPoseProvider(mode:factory:)`.
  - Routes configured providers through existing `runRecordedProvider(...)`.
  - Surfaces deterministic configuration failures as `Pose provider configuration failed: ...`.
  - Preserves recorded-run selection/source metadata when running configured recorded mode.
- `Tests/CamiFitAppTests/AppPoseProviderFactoryTests.swift`
  - Proves recorded-run mode preserves existing catalog behavior.
  - Proves mock-worker mode feeds app session summary and overlay state.
  - Proves missing mock worker path surfaces a deterministic run diagnostic.
  - Proves missing recorded-run mode surfaces a deterministic configuration diagnostic.

## Factory Design

The factory is intentionally narrow:

```text
AppPoseProviderMode
-> AppPoseProviderFactory.configuredProvider(for:)
-> AppConfiguredPoseProvider(provider + selectedPresetID + metadata)
-> AppExerciseSessionViewModel.runConfiguredPoseProvider(...)
-> existing runRecordedProvider(...)
```

Recorded catalog mode remains the default-safe behavior and still uses recorded JSONL fixtures through `MediaPipePoseProvider`. Mock-worker mode explicitly requires a `pose_worker.py` URL and routes through `PoseWorkerSubprocessProvider` in `--mode mock`.

## Validation

Focused:

```sh
swift test --disable-sandbox --filter AppPoseProviderFactoryTests
```

Result: passed, 4 tests, 0 failures.

Evidence:

```text
app-provider-factory-missing-recorded frames=0 diagnostic=Pose provider configuration failed: recorded run not found: missing-recorded-run
app-provider-factory-missing-worker selected=bodyweight_squat frames=0 diagnostic=Pose provider failed: pose worker script not found: /Users/kelly/Developer/camifit/pose_worker/missing_pose_worker.py
app-provider-factory-mock fixture=squat_bottom selected=bodyweight_squat frames=1 reps=0 overlay_points=37 diagnostic=nil
app-provider-factory-recorded mode=squat_two_frames selected=bodyweight_squat frames=2 reps=0 source=/Users/kelly/Developer/camifit/.build/arm64-apple-macosx/debug/CamiFit_CamiFitApp.bundle/RecordedRuns diagnostic=nil
```

Broad:

```sh
swift build --disable-sandbox
swift test --disable-sandbox
scripts/audit_autonomous_workflow.sh
git diff --check -- Sources/CamiFitApp/AppPoseProviderFactory.swift Sources/CamiFitApp/AppExerciseSessionViewModel.swift Tests/CamiFitAppTests/AppPoseProviderFactoryTests.swift
```

Results:

- `swift build --disable-sandbox`: passed.
- `swift test --disable-sandbox`: passed, 102 tests, 0 failures.
- `scripts/audit_autonomous_workflow.sh`: workflow audit clean.
- `git diff --check`: passed.

Not run:

- `pytest` was not run because this slice did not modify `pose_worker/`.
- No SwiftUI app launch, live camera, screenshot, or on-screen overlay verification was attempted.

## Reachability

Mock worker product-path reachability proven by `testMockWorkerModeFeedsAppSessionAndOverlayState`:

```text
AppPoseProviderMode.mockWorker(...)
-> AppPoseProviderFactory.configuredProvider(for:)
-> PoseWorkerSubprocessProvider
-> /usr/bin/env python3 pose_worker/pose_worker.py --mode mock
-> JSONL health/predict
-> MediaPipePoseJSONLDecoder
-> PoseFrame
-> AppExerciseSessionViewModel.runConfiguredPoseProvider(...)
-> runRecordedProvider(...)
-> AppPoseProviderSession
-> app summary + HUD/overlay state
```

Recorded-run reachability proven by `testRecordedRunModeUsesCatalogProviderAndPreservesRecordedBehavior`:

```text
AppPoseProviderMode.recordedRun(id: "squat_two_frames")
-> AppPoseProviderFactory.configuredProvider(for:)
-> AppRecordedRunCatalog
-> MediaPipePoseProvider
-> AppExerciseSessionViewModel.runConfiguredPoseProvider(...)
-> runRecordedProvider(...)
-> AppPoseProviderSession
```

## Flags For Reviewer

- This adds an app-level selection/configuration boundary only; it does not add UI controls in `ContentView`.
- Mock worker mode only; no `mediapipe` worker mode was wired or claimed.
- No live camera capture path was implemented.
- No model download, `pip install`, or Python environment mutation was performed.
- No `pose_worker/` source files were changed.
- No SwiftUI app-run verification was performed.

## Next Suggested Slice

Add a minimal explicit SwiftUI command/control for the mock-worker mode that calls `runConfiguredPoseProvider(...)`, while keeping recorded-run controls unchanged and still avoiding live camera or MediaPipe model mode.
