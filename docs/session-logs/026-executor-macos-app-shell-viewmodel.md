# Session Log 026 - Executor - macOS App Shell + View Model Boundary

**Date:** 2026-06-03  
**Role:** Executor  
**Slice:** `docs/briefs/026-macos-app-shell-viewmodel.md`  
**Commit:** final scoped slice commit in git history

## Summary

Started M3 with a SwiftPM macOS executable target and a testable app-facing session view model. The slice establishes the app boundary for exercise selection and recorded-frame processing without launching the app, opening the camera, spawning `pose_worker.py`, downloading models, or claiming live UI behavior.

## Files Changed

- `Package.swift`
- `Sources/CamiFitApp/CamiFitApp.swift`
- `Sources/CamiFitApp/ContentView.swift`
- `Sources/CamiFitApp/AppExerciseSessionViewModel.swift`
- `Tests/CamiFitAppTests/AppExerciseSessionViewModelTests.swift`
- `docs/session-logs/026-executor-macos-app-shell-viewmodel.md`

## Package / Target Notes

- Added executable product `CamiFitApp`.
- Added executable target `CamiFitApp` depending on `CamiFitEngine`.
- Added test target `CamiFitAppTests` depending on `CamiFitApp` and `CamiFitEngine`.
- SwiftPM successfully built and linked the executable target during focused and broad validation.
- The package remains SwiftPM-first; no Xcode project generation, app packaging, signing, notarization, or live app run was attempted.

## Implementation Notes

- Added a minimal SwiftUI `@main` entry point and root `ContentView`.
- Kept `ContentView` thin:
  - loads available presets on appear;
  - exposes an exercise picker;
  - displays rep count, hold progress, score, cue, and diagnostics.
- Added `AppExerciseSessionViewModel`:
  - lists loadable preset JSON files from an injected `Presets/` directory;
  - selects presets through `ProgramLoader`;
  - accepts recorded `[PoseFrame]` sequences;
  - runs frames through `EngineTraceRecorder`;
  - exposes app-facing state for selected exercise, reps, hold seconds, target reached, cue, score, and diagnostics.
- Tests inject the repo-local `Presets/` directory and load checked-in fixtures from `Tests/CamiFitEngineTests/Fixtures/`.

## Validation

Focused:

```bash
swift test --disable-sandbox --filter AppExerciseSessionViewModelTests
```

Result:

```text
Executed 4 tests, with 0 failures (0 unexpected)
app-viewmodel-presets bodyweight_lunge:reps,bodyweight_plank:hold,bodyweight_pushup:reps,bodyweight_squat:reps
app-viewmodel-squat fixture=synthetic_squat_clean_trace reps=1 score=nil diagnostic=nil
app-viewmodel-plank fixture=synthetic_plank_clean_hold_trace held=1.0 target=true score=1.000 diagnostic=nil
app-viewmodel-invalid fixture=synthetic_plank_low_visibility_trace final_held=0.5 final_target=false invalid_diagnostic=hold signal plank_line invalid: filter plank_line source plank_line_raw invalid: low confidence landmark primary.hip visibility=0.2 presence=1.0 threshold=0.65
```

Broad:

```bash
swift build --disable-sandbox
```

Result:

```text
Build complete!
```

```bash
swift test --disable-sandbox
```

Result:

```text
Executed 76 tests, with 0 failures (0 unexpected)
```

Workflow audit:

```bash
scripts/audit_autonomous_workflow.sh
```

Result:

```text
workflow audit clean
```

## Reachability

The app tests prove the requested app-layer path:

```text
AppExerciseSessionViewModel.loadAvailablePresets()
  -> app exercise selection
  -> ProgramLoader.load(Presets/*.json)
  -> checked-in PoseFrame fixture
  -> EngineTraceRecorder.record(frames:)
  -> AppExerciseSessionState
```

The tests do not call `HoldEvaluator` or `RepStateMachine` directly.

## Evidence

Preset listing:

- `bodyweight_lunge: reps`
- `bodyweight_plank: hold`
- `bodyweight_pushup: reps`
- `bodyweight_squat: reps`

Squat app path:

- selected preset: `bodyweight_squat` / `Bodyweight Squat`
- fixture: `synthetic_squat_clean_trace.json`
- final rep count: `1`
- hold seconds: `0`
- target reached: `false`
- diagnostic: `nil`

Plank app path:

- selected preset: `bodyweight_plank` / `Bodyweight Plank`
- fixture: `synthetic_plank_clean_hold_trace.json`
- final hold seconds: `1.0`
- target reached: `true`
- score: `1.000`
- diagnostic: `nil`

Invalid app path:

- selected preset: `bodyweight_plank` / `Bodyweight Plank`
- fixture: `synthetic_plank_low_visibility_trace.json`
- full fixture final hold seconds: `0.5`
- full fixture final target reached: `false`
- through invalid frame hold seconds: `0`
- through invalid frame target reached: `false`
- diagnostic includes: `low confidence landmark primary.hip`

## Flags For Reviewer

- The executable target is buildable through SwiftPM, but this slice intentionally does not run the SwiftUI app.
- `AppExerciseSessionViewModel` defaults its preset directory to `cwd/Presets`; tests inject an absolute repo path. A later app-bundling slice should decide how presets are copied into app resources for packaged runs.
- The invalid full-fixture final state has recovered to `0.5s` after the invalid frame, so the test also processes through the invalid frame to prove diagnostic exposure at the failure point.
- Existing unrelated untracked files were present and left untouched:
  - `docs/prd/`
  - `docs/research/2026-06-03-chatgpt-pro-pose-stack-response.md`
  - `docs/research/2026-06-03-chatgpt-pro-pose-stack-source-links.json`

## Next Suggested Slice

Add an app resource/preset-loading slice that makes preset discovery robust for packaged app execution, or add a headlessly tested pose-provider-to-view-model adapter before any live camera or human run-verification step.
