# Brief 039: App Preflight Preserves Completed Run

## Objective

Add one narrow deterministic regression proving mock-worker preflight does not disturb an already completed app run.

The prior slice proved preflight does not mutate an initially empty run state. Before preparing a human-run SwiftUI verification checklist, prove the same property after the app has real summary/HUD/overlay/provider-status state from a completed command.

## Scope

- Add a focused test that first runs an existing deterministic command, such as `runMockWorkerProvider(...)` or `runRecordedRun(id:)`.
- Capture the resulting:
  - `lastPoseProviderRunSummary`
  - `latestHUDState`
  - `latestPoseOverlayState`
  - `poseProviderRunStatus`
- Call `preflightMockWorker(...)` with a successful repo-local mock worker.
- Assert the captured run summary, HUD, overlay, and provider run status are unchanged after successful preflight.
- Add a matching failure-path assertion if it stays small: after a completed run, a missing-worker preflight should fail preflight status without changing completed-run state.
- Prefer tests only. Adjust production code only if the test exposes a real mutation bug.

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

- Focused preflight preservation test passes after a completed deterministic run.
- Existing `AppMockWorkerPreflightTests` remain green.
- Existing mock-worker run command, provider status, recorded-run catalog, HUD, overlay, and provider factory tests remain green.
- `swift build --disable-sandbox` passes.
- `swift test --disable-sandbox --filter AppMockWorkerPreflightTests` passes.
- `swift test --disable-sandbox` passes.
- `git diff --check` passes.

## Logging Requirements

The executor session log must include:

- Files changed.
- Exact validation commands and results.
- Evidence line showing completed-run state preserved across preflight.
- A short boundary statement confirming no live app launch, screenshot, camera run, `pose_worker/` change, pytest run, model download, or `pip install` occurred.
