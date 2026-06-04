# Executor Session Log 030 - App Recorded Run Catalog

**Date:** 2026-06-03  
**Role:** Executor  
**Brief:** `docs/briefs/030-app-recorded-run-catalog.md`  
**Commit:** pending at log time

## Slice

Implemented one smallest useful app-owned recorded-run catalog and command path. The app can now discover packaged recorded-run resources and run them through the existing `AppExerciseSessionViewModel.runRecordedProvider` path.

This stayed headless and deterministic:

- no live camera access;
- no `pose_worker.py` spawn;
- no model download;
- no network;
- no SwiftUI app run;
- no async streaming or cancellation;
- no `pose_worker/` changes.

## Files Changed

- `Package.swift`
  - Added `Resources/RecordedRuns` as a copied `CamiFitApp` target resource directory.
- `Sources/CamiFitApp/Resources/RecordedRuns/squat_two_frames.jsonl`
  - App-packaged clean two-frame squat recorded run copied from the existing checked-in MediaPipe fixture.
- `Sources/CamiFitApp/Resources/RecordedRuns/squat_mixed_no_pose.jsonl`
  - App-packaged mixed no-pose squat recorded run copied from the existing checked-in MediaPipe fixture.
- `Sources/CamiFitApp/AppRecordedRunCatalog.swift`
  - Added `AppRecordedRunSummary` and `AppRecordedRunCatalog`.
  - Catalog resolves two known app resource runs and fails closed when files are missing.
- `Sources/CamiFitApp/AppExerciseSessionViewModel.swift`
  - Added recorded-run catalog state.
  - Added `loadRecordedRuns()` and `runRecordedRun(id:)`.
  - Added recorded-run source injection for missing-resource tests.
- `Sources/CamiFitApp/ContentView.swift`
  - Added a thin recorded-run picker and run button bound to view-model commands.
  - No fixture paths, camera APIs, or process-spawning behavior were added.
- `Tests/CamiFitAppTests/AppRecordedRunCatalogTests.swift`
  - Added focused catalog and command tests.
- `docs/session-logs/030-executor-app-recorded-run-catalog.md`
  - This evidence log.

## Focused Validation

Command:

```bash
swift test --disable-sandbox --filter AppRecordedRunCatalogTests
```

Result:

- Pass.
- `AppRecordedRunCatalogTests`: 4 tests, 0 failures.

Evidence:

```text
app-recorded-runs source=/Users/kelly/Developer/camifit/.build/arm64-apple-macosx/debug/CamiFit_CamiFitApp.bundle/RecordedRuns runs=squat_two_frames:bodyweight_squat:cleanSample,squat_mixed_no_pose:bodyweight_squat:noPoseDiagnostic
app-recorded-run-clean id=squat_two_frames name=Squat sample source=/Users/kelly/Developer/camifit/.build/arm64-apple-macosx/debug/CamiFit_CamiFitApp.bundle/RecordedRuns preset=bodyweight_squat frames=2 reps=0 diagnostic=nil
app-recorded-run-no-pose id=squat_mixed_no_pose name=Squat no-pose sample source=/Users/kelly/Developer/camifit/.build/arm64-apple-macosx/debug/CamiFit_CamiFitApp.bundle/RecordedRuns preset=bodyweight_squat frames=3 reps=0 diagnostic=phase signal knee invalid: filter knee source knee_raw invalid: missing landmark primary.hip
app-recorded-run-missing source=nil requested=squat_two_frames frames=0 state_diagnostic=No recorded runs found summary_diagnostic=Recorded run not found: squat_two_frames
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
- `Executed 88 tests, with 0 failures (0 unexpected)`

Command:

```bash
git diff --check -- Package.swift Sources/CamiFitApp/AppRecordedRunCatalog.swift Sources/CamiFitApp/AppExerciseSessionViewModel.swift Sources/CamiFitApp/ContentView.swift Tests/CamiFitAppTests/AppRecordedRunCatalogTests.swift docs/session-logs/030-executor-app-recorded-run-catalog.md
```

Result:

- Pass, no output.

## Reachability Proof

The focused tests prove this app resource path:

```text
AppExerciseSessionViewModel()
  -> Bundle.module/RecordedRuns
  -> AppRecordedRunCatalog
  -> selected recorded run id squat_two_frames
  -> MediaPipePoseProvider(jsonlURL: app resource)
  -> AppExerciseSessionViewModel.runRecordedProvider(...)
  -> AppPoseProviderSession
  -> AppExerciseSessionViewModel.process(frames:)
  -> lastPoseProviderRunSummary / app-facing state
  -> ContentView recorded-run binding
```

The no-pose recorded run proves fail-closed diagnostic evidence from packaged app resources:

```text
runRecordedRun(id: squat_mixed_no_pose)
  -> app resource URL under CamiFit_CamiFitApp.bundle/RecordedRuns
  -> frameCount = 3
  -> selected preset = bodyweight_squat / Bodyweight Squat
  -> repCount = 0
  -> diagnostic includes missing landmark primary.hip
```

The missing-resource test proves fail-closed behavior:

```text
AppExerciseSessionViewModel(recordedRunsDirectory: missing-recorded-runs)
  -> loadRecordedRuns()
  -> availableRecordedRuns = []
  -> state diagnostic = No recorded runs found
  -> runRecordedRun(id: squat_two_frames)
  -> summary diagnostic = Recorded run not found: squat_two_frames
```

## Flags For Reviewer

- `ContentView` now has a recorded-run picker and run button, but it remains deterministic and resource-backed.
- The picker selection currently invokes `runRecordedRun(id:)` as a command; the button also runs the selected catalog item. This keeps the shell wired without adding live behavior.
- Recorded-run JSONL files are small copies of existing checked-in fixtures. This mirrors the preset-resource strategy from slice 027 and keeps app resources self-contained.
- Tests do not call `EngineTraceRecorder` directly and do not construct raw `[PoseFrame]` arrays.
- No live app/camera behavior is claimed.
- No `pose_worker/` files were modified, so pytest was not run.
- Pre-existing unrelated untracked docs remained untouched:
  - `docs/prd/`
  - `docs/research/2026-06-03-chatgpt-pro-pose-stack-response.md`
  - `docs/research/2026-06-03-chatgpt-pro-pose-stack-source-links.json`

## Next Suggested Slice

Add a headless skeleton/HUD state adapter for the latest processed pose/run summary, or prepare a human-run verification checklist for the packaged app shell once Reviewer confirms the recorded-run catalog path is sufficient.
