# Brief 034: App Pose Provider Factory

## Objective

Add an app-level pose-provider factory/configuration boundary so the SwiftUI shell can explicitly select a deterministic provider mode, including the mock subprocess provider from brief 033, without enabling live camera or MediaPipe model mode.

## Scope

- Add an app-layer provider configuration type, such as `AppPoseProviderMode` or `AppPoseProviderConfiguration`.
- Support at least:
  - recorded app catalog runs as the existing default-safe path;
  - mock subprocess worker provider using `pose_worker/pose_worker.py --mode mock`.
- Add a small factory/coordinator that produces a `PoseProvider` for the selected mode and routes it through the existing `AppExerciseSessionViewModel.runRecordedProvider(...)` or an equivalently named app command.
- Keep the factory injectable/testable; tests should not require launching the SwiftUI app.
- Surface deterministic diagnostics when the mock worker path is unavailable or provider creation/running fails.
- If touching `ContentView`, keep UI changes minimal and explicit, such as a provider-mode picker or a separate "Run Mock Worker" command.

## Out Of Scope

- No live camera capture.
- No `mediapipe` worker mode.
- No model downloads.
- No `pip install` or Python environment mutation.
- No `pose_worker.py` changes.
- No SwiftUI app launch, screenshot, or visual verification claim.
- No long-running streaming/cancellation architecture.

## Acceptance Criteria

- Tests prove the app can select/create the mock subprocess provider through the new factory/configuration boundary.
- Tests prove the selected mock provider feeds the app session path and updates summary/HUD/overlay state.
- Tests prove provider creation or run failure surfaces a deterministic diagnostic without crashing.
- Existing recorded-run catalog behavior remains unchanged and tested.
- Existing subprocess provider tests and full Swift suite remain green.
- The executor session log explicitly states no live camera, MediaPipe mode, model download, `pip install`, or SwiftUI app-run verification was performed.

## Expected Files

- `Sources/CamiFitApp/AppPoseProviderFactory.swift` or similar.
- `Sources/CamiFitApp/AppExerciseSessionViewModel.swift` if the command boundary belongs there.
- Optional narrow `Sources/CamiFitApp/ContentView.swift` changes.
- `Tests/CamiFitAppTests/AppPoseProviderFactoryTests.swift` or similar.
- `docs/session-logs/034-executor-app-pose-provider-factory.md`.

## Validation

Run and record:

```sh
swift build --disable-sandbox
swift test --disable-sandbox --filter AppPoseProviderFactoryTests
swift test --disable-sandbox
git diff --check
```

If the focused test name differs, record the exact command used.

Do not run or block on pytest unless this slice modifies `pose_worker/`; if that happens, stop and escalate for manager pytest handling.

## Session Log Requirements

In `docs/session-logs/034-executor-app-pose-provider-factory.md`, include:

- Files changed.
- Provider mode/factory design summary.
- Focused and full validation commands with outcomes.
- Evidence that mock subprocess mode reaches app session state.
- Evidence that failure diagnostics are deterministic.
- Confirmation that no live camera, MediaPipe mode, model download, `pip install`, or SwiftUI app-run verification was performed.
