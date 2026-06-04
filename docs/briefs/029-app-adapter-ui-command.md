# Slice Brief 029 - App Adapter UI Command

**Date:** 2026-06-03

## Objective

Wire the recorded `PoseProvider` adapter into the SwiftUI app shell through a testable app action or view-model command.

This slice should make the app shell capable of invoking the adapter path in a deterministic recorded-fixture mode. It must not access the live camera, spawn `pose_worker.py`, or claim a human-visible app run works.

## Product / Project Value

Slice 028 proved the adapter from recorded `PoseProvider` frames into app session state. The app shell still does not expose a command path that uses it. M3 needs that app-level command boundary before moving toward live camera and human run-verification.

## Scope

- Add an app-facing command or method that runs a recorded provider through `AppPoseProviderSession`.
  - This can live in `AppExerciseSessionViewModel`, a small coordinator, or a separate app model if cleaner.
  - Prefer dependency injection so tests can pass a fixture provider or throwing provider.
- Update `ContentView` only as much as needed to expose or bind the command state.
  - Keep the UI thin.
  - It is acceptable to expose a simple recorded-run button or status surface if it remains deterministic and does not imply live camera behavior.
- Add tests that prove:
  - the command selects an exercise and runs a recorded provider through the adapter;
  - command output updates app-facing state or a run summary visible to the view model;
  - provider failure surfaces a diagnostic;
  - no direct engine internals are called from tests.
- Keep this synchronous and batch-oriented. No async stream, cancellation, camera permission, subprocess, or app lifecycle work.

## Acceptance Criteria

- `swift build --disable-sandbox` passes.
- `swift test --disable-sandbox` passes.
- Focused command/view-model tests pass.
- The command path proves:
  - default app preset resources or explicit test injection;
  - selected preset id;
  - recorded `PoseProvider`;
  - `AppPoseProviderSession`;
  - app-facing state or summary update.
- Existing app adapter, resource/view-model, engine, and preset acceptance tests remain green.
- No live camera, `pose_worker.py` spawn, model download, network, app run, packaging/signing/notarization, Layer 2, or Layer 3 behavior is added.

## Expected Files

Likely files:

- `Sources/CamiFitApp/AppExerciseSessionViewModel.swift` or a new app coordinator/model file
- `Sources/CamiFitApp/ContentView.swift`
- `Tests/CamiFitAppTests/*Command*Tests.swift` or updates to existing app tests
- `docs/session-logs/029-executor-app-adapter-ui-command.md`

Do not modify `pose_worker/`. Do not retune presets or engine semantics.

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
- Focused command/view-model test result.
- For each command test:
  - selected preset id/name;
  - provider fixture or fake provider;
  - frame count;
  - final app-facing reps/hold state;
  - diagnostic/error text where applicable.
- Confirmation that no live app/camera/pose-worker behavior was claimed.

## Reachability / Demo Proof

The tests must prove:

```text
app command or view-model method
  -> AppPoseProviderSession
  -> PoseProvider fixture or fake provider
  -> AppExerciseSessionViewModel.process(frames:)
  -> app-facing state / run summary
  -> thin ContentView binding if UI changed
```

Do not prove this slice only by directly calling `EngineTraceRecorder` or constructing `[PoseFrame]` arrays.

## Out Of Scope

- Live camera capture.
- Spawning `pose_worker.py`.
- Async streaming or real-time frame loop.
- Skeleton overlay geometry.
- App packaging, signing, notarization, or App Store work.
- Human run-verification.
- Audio, persistence, Layer 2 agent authoring, Layer 3 history/progress.

## Stop Conditions

- ESCALATE if this command cannot be validated headlessly without running the SwiftUI app.
- ESCALATE before adding dependencies, generated project scaffolding, camera permissions, or process-spawning code.
- ESCALATE if a live SwiftUI app run becomes necessary to validate this slice.
