# Slice Brief 030 - App Recorded Run Catalog

**Date:** 2026-06-03

## Objective

Add a small app-owned recorded-run catalog and command path so the SwiftUI shell can trigger deterministic recorded provider runs without depending on test fixture paths.

This is still not live camera work. Do not spawn `pose_worker.py`, access camera APIs, run the SwiftUI app as proof, or claim live behavior.

## Product / Project Value

The app now has a recorded-provider command, but only tests know where recorded JSONL fixtures live. A packaged recorded-run catalog gives the app a deterministic demo/proof mode that uses app resources, exercises the same command path, and prepares the app shell for human-visible verification later without crossing into live camera yet.

## Scope

- Add app-target recorded-run resources, likely under `Sources/CamiFitApp/Resources/RecordedRuns/`.
  - Use small existing JSONL fixtures or narrow copies derived from existing checked-in fixtures.
  - Keep the resource set tiny: one valid squat JSONL and one mixed no-pose/fail-closed JSONL are enough.
- Add an app-facing recorded-run summary/catalog type, for example:
  - run id;
  - display name;
  - preset id;
  - resource URL;
  - expected purpose such as clean sample or no-pose diagnostic sample.
- Add a view-model command such as `loadRecordedRuns()` and `runRecordedRun(id:)`, or a small coordinator if cleaner.
- Update `ContentView` minimally to expose recorded-run state/control without making the UI look like live camera.
- Add tests proving:
  - default app resources discover recorded runs;
  - running the clean recorded run updates `lastPoseProviderRunSummary`;
  - running the no-pose recorded run preserves fail-closed diagnostic evidence;
  - missing/invalid recorded-run resources fail closed with a clear diagnostic;
  - no direct engine internals are called from tests.
- Keep the app command synchronous and batch-oriented.

## Acceptance Criteria

- `swift build --disable-sandbox` passes.
- `swift test --disable-sandbox` passes.
- Focused recorded-run catalog/command tests pass.
- Tests prove the path:
  - app recorded-run resources;
  - selected recorded run;
  - `MediaPipePoseProvider(jsonlURL:)`;
  - `AppExerciseSessionViewModel.runRecordedProvider`;
  - app-facing summary/state.
- Existing app command, adapter, resource/view-model, engine, and preset acceptance tests remain green.
- No live camera, `pose_worker.py` spawn, model download, network, app run, packaging/signing/notarization, Layer 2, or Layer 3 behavior is added.

## Expected Files

Likely files:

- `Package.swift` if resource declarations need to change
- `Sources/CamiFitApp/Resources/RecordedRuns/*.jsonl`
- `Sources/CamiFitApp/AppExerciseSessionViewModel.swift` or a new recorded-run catalog/coordinator file
- `Sources/CamiFitApp/ContentView.swift`
- `Tests/CamiFitAppTests/*RecordedRun*Tests.swift`
- `docs/session-logs/030-executor-app-recorded-run-catalog.md`

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
- Focused recorded-run catalog/command test result.
- For each recorded-run test:
  - recorded run id/name;
  - preset id/name;
  - resource URL source;
  - frame count;
  - final app-facing reps/hold state;
  - diagnostic/error text where applicable.
- Confirmation that no live app/camera/pose-worker behavior was claimed.

## Reachability / Demo Proof

The tests must prove:

```text
AppExerciseSessionViewModel()
  -> app packaged recorded-run resources
  -> recorded-run catalog
  -> selected recorded run id
  -> MediaPipePoseProvider(jsonlURL: app resource)
  -> runRecordedProvider(...)
  -> lastPoseProviderRunSummary / app-facing state
  -> thin ContentView binding if UI changed
```

Do not prove this slice only with absolute paths into `Tests/`.

## Out Of Scope

- Live camera capture.
- Spawning `pose_worker.py`.
- Async streaming or real-time frame loop.
- Skeleton overlay geometry.
- App packaging, signing, notarization, or App Store work.
- Human run-verification.
- Audio, persistence, Layer 2 agent authoring, Layer 3 history/progress.

## Stop Conditions

- ESCALATE if recorded-run resources cannot be packaged through SwiftPM target resources without generated project scaffolding.
- ESCALATE before adding dependencies, camera permissions, subprocess code, or live-app run requirements.
- ESCALATE if a live SwiftUI app run becomes necessary to validate this slice.
