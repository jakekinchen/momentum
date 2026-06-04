# Session Log 027 - Executor - App Preset Resources

**Date:** 2026-06-03  
**Role:** Executor  
**Slice:** `docs/briefs/027-app-preset-resources.md`  
**Commit:** final scoped slice commit in git history

## Summary

Made app preset discovery use SwiftPM executable-target resources by default instead of relying on `cwd/Presets`. The app still supports injected preset directories for tests and development, and now fails closed when an injected directory is missing or invalid.

No live app run, camera access, `pose_worker.py` spawn, model download, network call, packaging, signing, notarization, or Layer 2/3 behavior was added.

## Files Changed

- `Package.swift`
- `Sources/CamiFitApp/AppExerciseSessionViewModel.swift`
- `Sources/CamiFitApp/Resources/Presets/bodyweight_lunge.json`
- `Sources/CamiFitApp/Resources/Presets/bodyweight_plank.json`
- `Sources/CamiFitApp/Resources/Presets/bodyweight_pushup.json`
- `Sources/CamiFitApp/Resources/Presets/bodyweight_squat.json`
- `Tests/CamiFitAppTests/AppExerciseSessionViewModelTests.swift`
- `docs/session-logs/027-executor-app-preset-resources.md`

## Implementation Notes

- Added SwiftPM resources to the `CamiFitApp` executable target:

```swift
resources: [
    .copy("Resources/Presets")
]
```

- Copied the four current preset JSON files into `Sources/CamiFitApp/Resources/Presets/` so `Bundle.module` can package them for the executable target.
- Updated `AppExerciseSessionViewModel()` to resolve preset source candidates in order:
  - `Bundle.module` resource directory named `Presets`
  - development fallback: `cwd/Presets`
- Kept explicit injection via `AppExerciseSessionViewModel(presetsDirectory:)` for focused tests and deterministic development paths.
- Added `resolvedPresetSourceURL` and `presetSourceDescription` so tests and UI state can expose where presets came from.
- Missing injected preset directories now fail closed with an empty preset list and diagnostic `No presets found`.

## Validation

Focused:

```bash
swift test --disable-sandbox --filter AppExerciseSessionViewModelTests
```

Result:

```text
Executed 6 tests, with 0 failures (0 unexpected)
app-viewmodel-default-resource source=/Users/kelly/Developer/camifit/.build/arm64-apple-macosx/debug/CamiFit_CamiFitApp.bundle/Presets presets=bodyweight_lunge,bodyweight_plank,bodyweight_pushup,bodyweight_squat held=1.0 target=true
app-viewmodel-missing-presets source=nil presets=0 diagnostic=No presets found
app-viewmodel-invalid fixture=synthetic_plank_low_visibility_trace final_held=0.5 final_target=false invalid_diagnostic=hold signal plank_line invalid: filter plank_line source plank_line_raw invalid: low confidence landmark primary.hip visibility=0.2 presence=1.0 threshold=0.65
app-viewmodel-presets bodyweight_lunge:reps,bodyweight_plank:hold,bodyweight_pushup:reps,bodyweight_squat:reps
app-viewmodel-plank fixture=synthetic_plank_clean_hold_trace held=1.0 target=true score=1.000 diagnostic=nil
app-viewmodel-squat fixture=synthetic_squat_clean_trace reps=1 score=nil diagnostic=nil
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
Executed 78 tests, with 0 failures (0 unexpected)
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

The new default app path is covered by tests:

```text
AppExerciseSessionViewModel()
  -> Bundle.module/Presets
  -> ProgramLoader.load(...)
  -> app preset summaries
  -> selected bodyweight_plank
  -> synthetic_plank_clean_hold_trace fixture frames
  -> EngineTraceRecorder
  -> AppExerciseSessionState
```

The default-resource test does not inject the repo `Presets/` path.

## Evidence

Default packaged/resource source:

```text
/Users/kelly/Developer/camifit/.build/arm64-apple-macosx/debug/CamiFit_CamiFitApp.bundle/Presets
```

Preset ids discovered through the default app initializer:

- `bodyweight_lunge`
- `bodyweight_plank`
- `bodyweight_pushup`
- `bodyweight_squat`

Default resource processing proof:

- selected preset: `bodyweight_plank`
- fixture: `synthetic_plank_clean_hold_trace.json`
- hold seconds: `1.0`
- target reached: `true`

Injected-directory proof:

- repo `Presets/` injection still discovers all four presets.
- squat fixture still produces `reps=1`.
- plank clean fixture still produces `held=1.0`, `target=true`.
- plank low-visibility through invalid frame still exposes a low-confidence `primary.hip` diagnostic.

Fail-closed proof:

- injected missing directory returns `0` presets.
- `resolvedPresetSourceURL == nil`.
- diagnostic: `No presets found`.

## SwiftPM Resource Constraint

SwiftPM generated a `CamiFit_CamiFitApp.bundle` resource bundle for the executable target and made it available through `Bundle.module`. To use that mechanism cleanly, resources need to live under the app target directory, so this slice copied the four preset JSON files into `Sources/CamiFitApp/Resources/Presets/`.

The repo-root `Presets/` files remain the design/source-of-truth files for engine acceptance tests. The copied app resources are a packaging copy that should be kept in sync by future preset changes or replaced later with a build-time sync if the preset set grows.

## Flags For Reviewer

- This slice does not run the SwiftUI app; validation is headless through SwiftPM build/test only.
- The copied preset resources introduce duplication. It is intentional for this narrow SwiftPM packaging slice, but future preset edits must update both locations unless a sync step is added.
- Existing unrelated untracked files were present and left untouched:
  - `docs/prd/`
  - `docs/research/2026-06-03-chatgpt-pro-pose-stack-response.md`
  - `docs/research/2026-06-03-chatgpt-pro-pose-stack-source-links.json`

## Next Suggested Slice

Add a headlessly tested pose-provider-to-view-model adapter that accepts a `PoseProvider` stream and feeds `AppExerciseSessionViewModel`, still without live camera access or `pose_worker.py` spawning. After that, prepare an explicit human run-verification checklist for the first live app run.
