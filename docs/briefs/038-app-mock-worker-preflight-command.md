# Brief 038: App Mock-Worker Preflight Command

## Objective

Add a minimal, deterministic app-side preflight command for the mock pose worker so the SwiftUI shell can verify the repo-local worker path and health before a user runs the mock-worker provider command.

This is still headless app wiring. It does not launch the SwiftUI app and does not move to live camera verification.

## Scope

- Add an app-facing preflight result/status model for the mock worker, or reuse the existing provider status model if that stays clear.
- Add an `AppExerciseSessionViewModel` command such as `preflightMockWorker(...)` that checks:
  - configured worker script path exists;
  - mock worker health can be reached through the existing worker/provider boundary;
  - deterministic failure diagnostics are surfaced for a missing worker path.
- Wire a small explicit `ContentView` control if useful, such as `Check Mock Worker`.
- Keep the existing `Run Mock Worker` command behavior unchanged.
- Add focused tests for:
  - successful repo-local mock-worker preflight;
  - missing worker path failure;
  - no mutation of the last run summary/HUD/overlay when only preflight is requested, unless the implementation deliberately documents and tests a different narrow behavior.

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

- Focused preflight tests pass for success and missing-worker failure.
- Existing mock-worker run command tests remain green.
- Existing provider status, recorded-run catalog, HUD, overlay, and provider factory tests remain green.
- `swift build --disable-sandbox` passes.
- `swift test --disable-sandbox --filter AppMockWorkerPreflight` or an equivalently focused preflight/status filter passes.
- `swift test --disable-sandbox` passes.
- `git diff --check` passes.

## Logging Requirements

The executor session log must include:

- Files changed.
- Exact validation commands and results.
- Evidence lines for mock-worker preflight success and missing-worker failure.
- A short boundary statement confirming no live app launch, screenshot, camera run, `pose_worker/` change, pytest run, model download, or `pip install` occurred.
