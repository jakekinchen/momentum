# Executor Session Log 029 - App Adapter UI Command

**Date:** 2026-06-03  
**Role:** Executor  
**Brief:** `docs/briefs/029-app-adapter-ui-command.md`  
**Commit:** pending at log time

## Slice

Implemented one smallest useful app command boundary that lets the app view model run an injected recorded `PoseProvider` through `AppPoseProviderSession`.

This stayed headless and deterministic:

- no live camera access;
- no `pose_worker.py` spawn;
- no model download;
- no network;
- no SwiftUI app run;
- no async streaming or cancellation;
- no `pose_worker/` changes.

## Files Changed

- `Sources/CamiFitApp/AppExerciseSessionViewModel.swift`
  - Added `lastPoseProviderRunSummary`.
  - Added `runRecordedProvider(_:selectedPresetID:)`, a synchronous command that loads presets, chooses the requested or current preset, invokes `AppPoseProviderSession`, stores the summary, and returns it.
- `Sources/CamiFitApp/AppPoseProviderSession.swift`
  - Added an explicit public initializer for `AppPoseProviderRunSummary` so the view model can create fail-closed command summaries.
- `Sources/CamiFitApp/ContentView.swift`
  - Added passive binding for recorded command state: frame count and latest command diagnostic.
  - Did not add fixture-specific UI, camera UI, or process-spawning behavior.
- `Tests/CamiFitAppTests/AppExerciseSessionCommandTests.swift`
  - Added focused command tests using `MediaPipePoseProvider(jsonlURL:)` fixtures and a fake throwing provider.
- `docs/session-logs/029-executor-app-adapter-ui-command.md`
  - This evidence log.

## Focused Validation

Command:

```bash
swift test --disable-sandbox --filter AppExerciseSessionCommandTests
```

Result:

- Pass.
- `AppExerciseSessionCommandTests`: 3 tests, 0 failures.

Evidence:

```text
app-command-squat fixture=mediapipe_pose_worker_two_frames.jsonl source=/Users/kelly/Developer/camifit/.build/arm64-apple-macosx/debug/CamiFit_CamiFitApp.bundle/Presets selected=bodyweight_squat frames=2 reps=0 diagnostic=nil
app-command-current-selection fixture=mediapipe_pose_worker_mixed_no_pose.jsonl selected=bodyweight_squat frames=3 reps=0 diagnostic=phase signal knee invalid: filter knee source knee_raw invalid: missing landmark primary.hip
app-command-provider-failure selected=bodyweight_squat frames=0 reps=0 diagnostic=Pose provider failed: recorded fixture unreadable
```

## Broad Validation

Command:

```bash
swift build --disable-sandbox
```

Result:

- Pass.
- `Build complete! (0.15s)`

Command:

```bash
swift test --disable-sandbox
```

Result:

- Pass.
- `Executed 84 tests, with 0 failures (0 unexpected)`

Command:

```bash
git diff --check -- Sources/CamiFitApp/AppExerciseSessionViewModel.swift Sources/CamiFitApp/AppPoseProviderSession.swift Sources/CamiFitApp/ContentView.swift Tests/CamiFitAppTests/AppExerciseSessionCommandTests.swift
```

Result:

- Pass, no output.

## Reachability Proof

The focused tests prove this app command path:

```text
AppExerciseSessionViewModel.runRecordedProvider(_:selectedPresetID:)
  -> default packaged/resource presets
  -> selected preset id bodyweight_squat
  -> AppPoseProviderSession
  -> MediaPipePoseProvider(jsonlURL: Tests/CamiFitEngineTests/Fixtures/mediapipe_pose_worker_two_frames.jsonl)
  -> AppExerciseSessionViewModel.process(frames:)
  -> AppExerciseSessionState and AppPoseProviderRunSummary
  -> lastPoseProviderRunSummary for ContentView binding
```

The current-selection test proves the command can use existing app selection:

```text
viewModel.selectPreset(id: bodyweight_squat)
  -> runRecordedProvider(provider)
  -> MediaPipe mixed no-pose fixture
  -> frameCount = 3
  -> repCount = 0
  -> diagnostic includes missing landmark primary.hip
```

The provider failure test proves the command fails closed:

```text
Throwing PoseProvider
  -> runRecordedProvider(_:selectedPresetID: bodyweight_squat)
  -> AppPoseProviderSession
  -> lastPoseProviderRunSummary
  -> diagnostic = Pose provider failed: recorded fixture unreadable
```

## Flags For Reviewer

- `ContentView` only binds summary state; it does not construct a fixture provider or trigger any live behavior.
- The command is synchronous and batch-oriented per brief 029.
- Tests do not call `EngineTraceRecorder` directly and do not construct raw `[PoseFrame]` arrays.
- No live app/camera behavior is claimed.
- No `pose_worker/` files were modified, so pytest was not run.
- Pre-existing unrelated untracked docs remained untouched:
  - `docs/prd/`
  - `docs/research/2026-06-03-chatgpt-pro-pose-stack-response.md`
  - `docs/research/2026-06-03-chatgpt-pro-pose-stack-source-links.json`

## Next Suggested Slice

Add a fixture-backed recorded-run control or coordinator path that can be exercised from the app shell without hardcoding test fixture paths into `ContentView`, still staying headless and avoiding live camera/process work until human run-verification is explicitly requested.
