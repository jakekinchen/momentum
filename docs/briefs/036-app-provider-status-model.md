# Brief 036: App Provider Status Model

## Objective

Add a small deterministic app-side provider/run status model so the SwiftUI shell can distinguish idle, running, succeeded, and failed command outcomes for recorded-run and mock-worker provider commands.

This slice keeps the app command surface headlessly testable. It must not claim live SwiftUI app behavior.

## Scope

- Add an app-facing status type, such as `AppPoseProviderRunStatus` or equivalent, with states for:
  - idle
  - running
  - succeeded, carrying enough summary data to identify command mode/source and frame count
  - failed, carrying deterministic diagnostic text and command mode/source
- Wire the status through the existing `AppExerciseSessionViewModel` command paths:
  - recorded-run command
  - configured pose-provider command
  - mock-worker command
- Keep command execution synchronous for this slice. A brief `running` transition is enough; do not add async streaming, cancellation, timers, or background task management.
- If useful, expose the status in `ContentView` with minimal text near the existing controls.
- Preserve existing HUD, overlay, preset, and recorded-run behavior.

## Out of Scope

- No live camera mode.
- No MediaPipe model download.
- No `pip install`.
- No changes under `pose_worker/`.
- No async streaming or cancellation model.
- No UI redesign.
- No SwiftUI app launch, screenshot, or visual verification claim.
- No Layer 2 agent-authoring or Layer 3 persistence work.

## Acceptance Criteria

- Tests prove the initial view-model status is idle.
- Tests prove recorded-run success updates status deterministically with the selected source/mode and frame count.
- Tests prove mock-worker success updates status deterministically with the selected source/mode and frame count.
- Tests prove a missing mock-worker path updates status to failed with deterministic diagnostic text.
- Existing recorded-run catalog, HUD, overlay, and provider factory tests remain green.
- `swift build --disable-sandbox` passes.
- Focused new tests pass.
- `swift test --disable-sandbox` passes.
- `git diff --check` passes.

## Logging Requirements

The executor session log must include:

- Files changed.
- Exact validation commands and results.
- A short boundary statement confirming no live app launch, screenshot, camera run, `pose_worker/` change, pytest run, model download, or `pip install` occurred.
