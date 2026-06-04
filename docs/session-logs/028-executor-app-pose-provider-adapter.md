# Executor Session Log 028 - App PoseProvider Adapter

**Date:** 2026-06-03  
**Role:** Executor  
**Brief:** `docs/briefs/028-app-pose-provider-adapter.md`  
**Commit:** pending at log time

## Slice

Implemented one smallest useful app-layer bridge from a recorded `PoseProvider` to `AppExerciseSessionViewModel`.

This slice stayed headless:

- no live camera access;
- no `pose_worker.py` spawn;
- no model download;
- no network;
- no SwiftUI app run;
- no `pose_worker/` changes.

## Files Changed

- `Sources/CamiFitApp/AppPoseProviderSession.swift`
  - Added `AppPoseProviderSession`, a synchronous batch adapter that accepts a `PoseProvider` and an `AppExerciseSessionViewModel`.
  - Added `AppPoseProviderRunSummary`, an app-facing summary containing frame count, selected exercise, final reps/hold state, diagnostic text, and final session state.
  - The adapter loads app presets, selects the requested preset, reads frames from the provider, feeds the view model's recorded-frame processing path, and preserves diagnostic evidence observed anywhere in the batch.
- `Tests/CamiFitAppTests/AppPoseProviderSessionTests.swift`
  - Added recorded JSONL provider tests through `MediaPipePoseProvider(jsonlURL:)`.
  - Added fake throwing provider coverage.
- `docs/session-logs/028-executor-app-pose-provider-adapter.md`
  - This evidence log.

## Focused Validation

Command:

```bash
swift test --disable-sandbox --filter AppPoseProviderSessionTests
```

Result:

- Pass.
- `AppPoseProviderSessionTests`: 3 tests, 0 failures.

Evidence:

```text
app-pose-provider-squat fixture=mediapipe_pose_worker_two_frames.jsonl source=/Users/kelly/Developer/camifit/.build/arm64-apple-macosx/debug/CamiFit_CamiFitApp.bundle/Presets selected=bodyweight_squat frames=2 reps=0 diagnostic=nil
app-pose-provider-no-pose fixture=mediapipe_pose_worker_mixed_no_pose.jsonl selected=bodyweight_squat frames=3 reps=0 diagnostic=phase signal knee invalid: filter knee source knee_raw invalid: missing landmark primary.hip
app-pose-provider-throwing selected=bodyweight_squat frames=0 reps=0 diagnostic=Pose provider failed: fixture unavailable
```

The first focused test proves default app preset resources were used:

```text
source=/Users/kelly/Developer/camifit/.build/arm64-apple-macosx/debug/CamiFit_CamiFitApp.bundle/Presets
```

## Broad Validation

Command:

```bash
swift build --disable-sandbox
```

Result:

- Pass.
- `Build complete! (0.16s)`

Command:

```bash
swift test --disable-sandbox
```

Result:

- Pass.
- `Executed 81 tests, with 0 failures (0 unexpected)`

Command:

```bash
git diff --check -- Sources/CamiFitApp/AppPoseProviderSession.swift Tests/CamiFitAppTests/AppPoseProviderSessionTests.swift
```

Result:

- Pass, no output.

## Reachability Proof

The focused tests prove this real product path:

```text
AppExerciseSessionViewModel()
  -> default packaged/resource presets
  -> select bodyweight_squat
  -> MediaPipePoseProvider(jsonlURL: Tests/CamiFitEngineTests/Fixtures/mediapipe_pose_worker_two_frames.jsonl)
  -> AppPoseProviderSession.run(selectedPresetID:)
  -> AppExerciseSessionViewModel.process(frames:)
  -> AppPoseProviderRunSummary / AppExerciseSessionState
```

The no-pose test proves the fail-closed path:

```text
MediaPipePoseProvider(jsonlURL: Tests/CamiFitEngineTests/Fixtures/mediapipe_pose_worker_mixed_no_pose.jsonl)
  -> AppPoseProviderSession
  -> bodyweight_squat selected
  -> 3 frames processed
  -> final reps = 0
  -> diagnostic evidence includes missing landmark primary.hip
```

The throwing-provider test proves provider failure is contained at the app adapter boundary:

```text
ThrowingPoseProvider
  -> AppPoseProviderSession
  -> bodyweight_squat selected from app presets
  -> frameCount = 0
  -> diagnostic = Pose provider failed: fixture unavailable
```

## Flags For Reviewer

- The adapter is intentionally synchronous and batch-oriented per brief 028.
- The adapter preserves the first diagnostic observed during a batch because the existing view model reports only final-frame diagnostic state. This is required for mixed no-pose fixtures where the final frame can be valid after a no-pose interval.
- No live app/camera behavior is claimed.
- No `pose_worker/` files were modified, so pytest was not run.
- Pre-existing unrelated untracked docs remained untouched:
  - `docs/prd/`
  - `docs/research/2026-06-03-chatgpt-pro-pose-stack-response.md`
  - `docs/research/2026-06-03-chatgpt-pro-pose-stack-source-links.json`

## Next Suggested Slice

Wire the adapter into the SwiftUI app shell behind a testable app action or lightweight view-model method, still without camera access or live app run-verification. Keep validation headless and escalate only when a real macOS app/camera run becomes necessary.
