# Slice Brief 028 - App PoseProvider Adapter

**Date:** 2026-06-03

## Objective

Add a headlessly tested app-layer adapter that accepts a `PoseProvider`, reads recorded pose frames, and feeds `AppExerciseSessionViewModel` / app session state.

This is not live camera work. Do not spawn `pose_worker.py`, do not access the camera, and do not run the SwiftUI app as proof.

## Product / Project Value

M3 needs a clear bridge from pose sources into the app session. The engine already has `PoseProvider` and `MediaPipePoseProvider(jsonlURL:)` for recorded JSONL. The app now has preset resources and a view-model boundary. This slice connects those two testable pieces before any live app run-verification.

## Scope

- Add an app-facing adapter type, for example `AppPoseProviderSession` or `AppPoseFrameRunner`, under `Sources/CamiFitApp/`.
- The adapter should:
  - accept a `PoseProvider`;
  - accept or own an `AppExerciseSessionViewModel`;
  - ensure a selected preset is loaded or report a clear diagnostic when it is not;
  - read frames from the provider in batch for this slice;
  - call the view model's recorded-frame processing path;
  - return app-facing state and/or a small run summary with frame count, selected exercise, final reps/hold state, and diagnostic text.
- Add tests using existing recorded JSONL fixtures:
  - `MediaPipePoseProvider(jsonlURL: mediapipe_pose_worker_two_frames.jsonl)` feeds the app adapter for squat and produces deterministic app state.
  - `MediaPipePoseProvider(jsonlURL: mediapipe_pose_worker_mixed_no_pose.jsonl)` preserves fail-closed/no-false-count behavior and surfaces diagnostic evidence.
  - A fake throwing provider causes a clear app-layer error/diagnostic without crashing.
  - The adapter uses the default app preset resource path at least once; do not rely only on injected repo `Presets/`.
- Keep processing synchronous/batch-oriented. Streaming, async tasks, live camera frames, cancellation, and UI lifecycle are later slices.

## Acceptance Criteria

- `swift build --disable-sandbox` passes.
- `swift test --disable-sandbox` passes.
- Focused app pose-provider adapter tests pass.
- Tests prove the path:
  - default app preset resources;
  - selected exercise;
  - `MediaPipePoseProvider` recorded JSONL fixture;
  - adapter;
  - `AppExerciseSessionViewModel`;
  - final app session state.
- Provider errors fail closed with explicit diagnostic/error state.
- Existing app resource/view-model, engine, and preset acceptance tests remain green.
- No live camera, `pose_worker.py` spawn, model download, network, app run, packaging/signing/notarization, Layer 2, or Layer 3 behavior is added.

## Expected Files

Likely files:

- `Sources/CamiFitApp/AppPoseProviderSession.swift`
- `Tests/CamiFitAppTests/AppPoseProviderSessionTests.swift`
- maybe `Sources/CamiFitApp/AppExerciseSessionViewModel.swift` for narrow support hooks
- `docs/session-logs/028-executor-app-pose-provider-adapter.md`

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
- Focused adapter test result.
- For each adapter test:
  - provider fixture or fake provider used;
  - selected preset id/name;
  - frame count;
  - final reps or hold state;
  - diagnostic/error text where applicable.
- Confirmation that no live app/camera/pose-worker behavior was claimed.

## Reachability / Demo Proof

The tests must prove:

```text
AppExerciseSessionViewModel()
  -> default packaged/resource presets
  -> select bodyweight_squat or bodyweight_plank
  -> MediaPipePoseProvider(jsonlURL: checked-in fixture)
  -> app pose-provider adapter
  -> AppExerciseSessionViewModel.process(frames:)
  -> app-facing session state
```

Do not prove the adapter only with direct `[PoseFrame]` arrays.

## Out Of Scope

- Live camera capture.
- Spawning `pose_worker.py`.
- Async streaming or real-time frame loop.
- SwiftUI lifecycle integration beyond minimal wiring if needed.
- Skeleton overlay geometry.
- App packaging, signing, notarization, or App Store work.
- Human run-verification.
- Audio, persistence, Layer 2 agent authoring, Layer 3 history/progress.

## Stop Conditions

- ESCALATE if the adapter requires changing the `PoseProvider` contract in a way that affects engine tests broadly.
- ESCALATE before adding dependencies, generated project scaffolding, camera permissions, or process-spawning code.
- ESCALATE if a live SwiftUI app run becomes necessary to validate this slice.
