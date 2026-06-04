# Brief 035: App Mock Worker UI Command

## Objective

Expose the mock-worker provider mode through a minimal SwiftUI app-shell command so the current app surface can explicitly invoke `pose_worker.py --mode mock` through the factory path. This should remain a wireable, headlessly tested UI command boundary, not a live app verification claim.

## Scope

- Add a minimal app command path for mock-worker mode, preferably on `AppExerciseSessionViewModel`, that builds an `AppPoseProviderMode.mockWorker(...)` and calls `runConfiguredPoseProvider(...)`.
- Wire a small explicit control into `ContentView`, such as a "Run Mock Worker" button or a provider-mode segmented control plus run button.
- Keep recorded-run controls unchanged unless a tiny cleanup is required.
- Keep the mock worker configuration deterministic and repo-local.
- Add tests for the view-model command path and any pure command state exposed to the view.
- If testing the SwiftUI view directly is not practical, test the view-model command and keep `ContentView` changes compile-only.

## Out Of Scope

- No live camera capture.
- No `mediapipe` worker mode.
- No model downloads.
- No `pip install` or Python environment mutation.
- No `pose_worker.py` changes.
- No SwiftUI app launch, screenshot, or visual verification claim.
- No long-running streaming/cancellation architecture.
- No UI redesign.

## Acceptance Criteria

- A clear mock-worker command exists in the app layer and routes through `AppPoseProviderFactory` / `runConfiguredPoseProvider(...)`.
- Tests prove the mock-worker command feeds app session summary, HUD, and overlay state.
- Tests prove deterministic failure diagnostics if the configured mock worker path is unavailable.
- Existing recorded-run command/catalog behavior remains green.
- Full Swift suite remains green.
- The executor session log explicitly states no live camera, MediaPipe mode, model download, `pip install`, SwiftUI app launch, screenshot, or visual verification was performed.

## Expected Files

- `Sources/CamiFitApp/AppExerciseSessionViewModel.swift`.
- `Sources/CamiFitApp/ContentView.swift`.
- Optional small app configuration/helper file if needed.
- `Tests/CamiFitAppTests/AppMockWorkerCommandTests.swift` or similar.
- `docs/session-logs/035-executor-app-mock-worker-ui-command.md`.

## Validation

Run and record:

```sh
swift build --disable-sandbox
swift test --disable-sandbox --filter AppMockWorkerCommandTests
swift test --disable-sandbox
git diff --check
```

If the focused test name differs, record the exact command used.

Do not run or block on pytest unless this slice modifies `pose_worker/`; if that happens, stop and escalate for manager pytest handling.

## Session Log Requirements

In `docs/session-logs/035-executor-app-mock-worker-ui-command.md`, include:

- Files changed.
- Command/control design summary.
- Focused and full validation commands with outcomes.
- Evidence that the mock-worker command reaches app session/HUD/overlay state.
- Evidence that failure diagnostics are deterministic.
- Confirmation that no live camera, MediaPipe mode, model download, `pip install`, SwiftUI app launch, screenshot, or visual verification was performed.
