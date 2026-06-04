# Slice Brief 026 - macOS App Shell + View Model Boundary (M3)

**Date:** 2026-06-03

## Objective

Start M3 by adding the smallest real macOS app surface that can be validated headlessly: a SwiftUI app target plus an engine-backed view-model boundary for exercise selection and recorded-frame processing.

This slice should create wireable app structure, not a claimed live-camera product. Live camera access, on-screen skeleton rendering, and a human-visible app run remain out of scope until a later explicit run-verification handoff.

## Product / Project Value

M2 proved the engine contract with squat, push-up, lunge, and plank presets. M3 now needs the app layer that will eventually connect camera frames to engine output. The first app slice should establish a stable boundary the later UI/camera work can depend on while staying testable in the autonomous loop.

## Scope

- Add a macOS executable/app target in `Package.swift` if SwiftPM can support the chosen structure cleanly.
- Add a minimal SwiftUI app entry point and root view under a new app target directory, for example `Sources/CamiFitApp/`.
- Add an app-facing model/view-model layer that:
  - lists available bundled presets from the known local `Presets/` directory;
  - loads a selected preset through `ProgramLoader`;
  - accepts recorded `PoseFrame` sequences in tests;
  - runs the frames through `EngineTraceRecorder`;
  - exposes a compact UI state such as selected exercise name, rep count or hold progress, cue text, score, and invalid/diagnostic text.
- Add tests for the view-model logic using checked-in fixtures, without launching a live app or camera:
  - selection loads squat and plank at minimum;
  - squat fixture updates rep count from the trace;
  - plank clean fixture updates hold progress / target reached;
  - invalid fixture exposes diagnostic evidence and does not claim success.
- Keep the SwiftUI view thin. Prefer testing the app model/view-model directly rather than snapshotting UI.

## Acceptance Criteria

- `swift build --disable-sandbox` passes.
- `swift test --disable-sandbox` passes.
- The package exposes a buildable macOS app/executable target without breaking the existing `CamiFitEngine` library product.
- App model tests prove preset selection and fixture-driven engine summaries without direct `HoldEvaluator` or `RepStateMachine` calls.
- The implementation does not access the camera, spawn `pose_worker.py`, require a model download, use network APIs, or run the SwiftUI app as proof.
- Existing engine and preset acceptance tests remain green.

## Expected Files

Likely files:

- `Package.swift`
- `Sources/CamiFitApp/CamiFitApp.swift`
- `Sources/CamiFitApp/ContentView.swift`
- `Sources/CamiFitApp/AppExerciseSessionViewModel.swift`
- `Tests/CamiFitAppTests/AppExerciseSessionViewModelTests.swift`
- `docs/session-logs/026-executor-macos-app-shell-viewmodel.md`

Adjust paths if SwiftPM app-target conventions require a cleaner local structure, but keep the slice narrow.

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
- Focused app view-model test result.
- For each tested preset/fixture:
  - selected preset id/name;
  - fixture used;
  - final rep count or hold seconds / target state;
  - cue/score/invalid diagnostic summary where applicable.
- Any SwiftPM app-target constraint discovered while adding the target.

## Reachability / Demo Proof

The tests must prove the intended app-layer path:

```text
app exercise selection
  -> ProgramLoader.load(...)
  -> checked-in PoseFrame fixture
  -> EngineTraceRecorder.record(frames:)
  -> app-facing session state
```

Do not prove this slice only by constructing engine internals directly.

## Out Of Scope

- Live camera capture.
- Spawning `pose_worker.py`.
- MediaPipe model download or install steps.
- Skeleton overlay geometry.
- Production visual polish.
- App packaging, signing, notarization, or TestFlight/App Store work.
- Audio, persistence, Layer 2 agent authoring, Layer 3 history/progress.
- Human run-verification. If a live app run becomes necessary to proceed, ESCALATE with an exact command/checklist instead of claiming it works.

## Stop Conditions

- ESCALATE if SwiftPM cannot express a viable macOS app target without switching project structure or introducing Xcode project generation.
- ESCALATE before adding external dependencies or generated project scaffolding.
- ESCALATE if live camera or running SwiftUI behavior becomes necessary to validate the slice.
