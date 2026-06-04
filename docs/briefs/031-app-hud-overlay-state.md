# Brief 031: App HUD Overlay State

## Objective

Add app-facing, display-ready state for the macOS exercise HUD and pose overlay, derived from deterministic recorded pose frames and engine output. This should move M3 toward "live skeleton + rep/form HUD" while staying fully headless and unit-testable.

## Scope

- Add an app-layer state/model type for overlay primitives from a `PoseFrame`, such as normalized landmark points or named joint segments suitable for a SwiftUI skeleton overlay.
- Add an app-layer HUD summary state derived from the current/last app session output, including at least preset name/id, frame count, rep count or set progress, and diagnostic/cue text when present.
- Wire the state through `AppExerciseSessionViewModel` so `runRecordedRun(id:)` updates the latest overlay/HUD state after a recorded run.
- Use the existing app recorded-run catalog/resources and `MediaPipePoseProvider` JSONL path for tests.
- Keep `ContentView` changes minimal and only if useful for exposing existing state; do not attempt a polished live UI.

## Out Of Scope

- No live camera capture.
- No `pose_worker.py` changes.
- No network model downloads or dependency installation.
- No Layer 2 agent authoring.
- No Layer 3 persistence/history.
- No claims that the running SwiftUI app overlay works; anything requiring visual app verification remains a human boundary.

## Acceptance Criteria

- Tests prove a clean recorded app run produces nonempty overlay state from the latest pose frame.
- Tests prove the overlay state is normalized/display-ready and fails closed or omits invalid low-visibility/no-pose landmarks.
- Tests prove HUD state updates after a clean recorded run with the selected preset id/name and frame/rep summary.
- Tests prove the no-pose recorded run preserves diagnostic/cue evidence in HUD state without fabricating overlay points.
- Existing app recorded-run catalog tests remain green.

## Expected Files

- `Sources/CamiFitApp/AppPoseOverlayState.swift` or similar.
- `Sources/CamiFitApp/AppHUDState.swift` or similar.
- `Sources/CamiFitApp/AppExerciseSessionViewModel.swift`.
- Optional narrow `Sources/CamiFitApp/ContentView.swift` changes.
- `Tests/CamiFitAppTests/AppHUDOverlayStateTests.swift` or similar.
- `docs/session-logs/031-executor-app-hud-overlay-state.md`.

## Validation

Run and record:

```sh
swift build --disable-sandbox
swift test --disable-sandbox --filter AppHUDOverlayStateTests
swift test --disable-sandbox
git diff --check
```

If a test name differs, record the exact focused test command used.

## Session Log Requirements

In `docs/session-logs/031-executor-app-hud-overlay-state.md`, include:

- Files changed.
- Design summary for overlay/HUD state.
- Focused and full validation commands with outcomes.
- Evidence from recorded resources showing clean overlay/HUD output.
- Evidence that no-pose/invalid landmark data fails closed.
- Explicit note that live SwiftUI/camera behavior was not claimed or verified.
