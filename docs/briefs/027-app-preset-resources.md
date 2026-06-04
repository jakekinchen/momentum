# Slice Brief 027 - App Preset Resources

**Date:** 2026-06-03

## Objective

Make preset discovery robust for app execution by moving the app target away from a fragile `cwd/Presets` assumption and into an explicit, testable resource-loading path.

Stay headless. Do not run the SwiftUI app as proof, do not access the camera, and do not spawn `pose_worker.py`.

## Product / Project Value

Slice 026 established the app shell and session view model, but the default app path only finds presets when the process current directory is the repo root. M3 needs the app to be runnable outside that assumption before live camera or human run-verification work can be meaningful.

## Scope

- Add a packaged preset resource strategy for `CamiFitApp`:
  - Prefer SwiftPM target resources if they work cleanly for the executable target.
  - Keep a repo-directory fallback only if useful for development, but make the packaged/resource path the primary app default.
- Keep the existing `Presets/*.json` files as the single source of truth, or add a narrow copy/symlink/resource layout if SwiftPM requires resources to live under the app target.
- Update `AppExerciseSessionViewModel` initialization so default app preset loading does not depend on `FileManager.default.currentDirectoryPath`.
- Add tests that prove:
  - the default view model can discover presets without injecting the repo `Presets/` path;
  - injected directories still work for focused tests;
  - missing/invalid resource directories fail closed with an empty preset list or explicit state, not a crash;
  - squat/plank fixture processing still works after the resource-loading change.
- Record any SwiftPM resource constraints in the executor log.

## Acceptance Criteria

- `swift build --disable-sandbox` passes.
- `swift test --disable-sandbox` passes.
- Focused app resource/view-model tests pass.
- Default app preset discovery is test-covered and no longer relies only on `cwd/Presets`.
- Existing app view-model, engine, and preset acceptance tests remain green.
- No camera access, `pose_worker.py` spawn, model download, network call, app packaging/signing/notarization, or live app run is added.

## Expected Files

Likely files:

- `Package.swift`
- `Sources/CamiFitApp/AppExerciseSessionViewModel.swift`
- resource files or resource copy location required by SwiftPM
- `Tests/CamiFitAppTests/AppExerciseSessionViewModelTests.swift`
- optional new focused resource tests under `Tests/CamiFitAppTests/`
- `docs/session-logs/027-executor-app-preset-resources.md`

Keep changes narrow. Do not retune exercise presets or engine logic.

## Validation Commands

```bash
cd /Users/kelly/Developer/camifit
swift build --disable-sandbox
swift test --disable-sandbox
```

Do not run or block on pytest unless this slice unexpectedly modifies `pose_worker/`, in which case ESCALATE for a manager pytest run.

## Evidence To Record

- `swift build --disable-sandbox` result.
- `swift test --disable-sandbox` test count and pass/fail.
- Focused app resource/view-model test result.
- The resolved default preset source used by the app path.
- Preset ids discovered through the default app initializer.
- Failure behavior for a missing/invalid preset resource location.
- Confirmation that no live app/camera/pose-worker behavior was claimed.

## Reachability / Demo Proof

The tests must prove:

```text
AppExerciseSessionViewModel()
  -> default packaged/resource preset source
  -> ProgramLoader.load(...)
  -> app preset summaries
  -> selected preset
  -> fixture frames
  -> EngineTraceRecorder
  -> app-facing state
```

Do not prove resource loading only through an injected absolute repo path.

## Out Of Scope

- Live camera capture.
- Spawning `pose_worker.py`.
- MediaPipe model download or install steps.
- Skeleton overlay geometry.
- App packaging, signing, notarization, or App Store work.
- Human run-verification.
- Audio, persistence, Layer 2 agent authoring, Layer 3 history/progress.

## Stop Conditions

- ESCALATE if SwiftPM executable-target resources cannot support a clean packaged preset path without switching to an Xcode project or generated project scaffolding.
- ESCALATE before adding external dependencies or generated project scaffolding.
- ESCALATE if a live SwiftUI app run becomes necessary to validate this slice.
