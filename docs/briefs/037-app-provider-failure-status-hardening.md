# Brief 037: App Provider Failure Status Hardening

## Objective

Harden deterministic status coverage for app provider failures before moving toward human-run SwiftUI verification.

The prior slice added the status model and covered recorded-run success, mock-worker success, and missing mock-worker failure. This slice closes the remaining command-path gaps: direct provider failures and configured-provider failures should also produce stable failed statuses with useful descriptors.

## Scope

- Add focused tests proving `AppExerciseSessionViewModel.runRecordedProvider(...)` updates `poseProviderRunStatus` to `.failed` when the injected provider throws.
- Add focused tests proving `AppExerciseSessionViewModel.runConfiguredPoseProvider(...)` updates `poseProviderRunStatus` to `.failed` when provider configuration fails, such as a missing recorded-run ID.
- Assert deterministic descriptor fields for those failures:
  - direct provider path: mode/source should clearly identify direct provider execution.
  - configured recorded-run path: mode/source should identify the requested recorded-run ID.
- Assert deterministic diagnostic text is preserved in the status failure payload and still reaches the existing summary/HUD state.
- Keep existing status success tests green.
- Prefer tests first. Only adjust product code if the tests expose a real descriptor/status mismatch.

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

- Focused failure-status tests pass for:
  - direct provider throwing/failing path
  - configured provider missing recorded-run path
- Existing `AppPoseProviderRunStatusTests` remain green.
- Existing recorded-run catalog, HUD, overlay, mock-worker, and provider factory tests remain green.
- `swift build --disable-sandbox` passes.
- `swift test --disable-sandbox --filter AppPoseProviderRunStatusTests` passes, or the new tests are included under an equivalently focused status-test filter.
- `swift test --disable-sandbox` passes.
- `git diff --check` passes.

## Logging Requirements

The executor session log must include:

- Files changed.
- Exact validation commands and results.
- Evidence lines for the direct-provider failure status and configured-provider failure status.
- A short boundary statement confirming no live app launch, screenshot, camera run, `pose_worker/` change, pytest run, model download, or `pip install` occurred.
