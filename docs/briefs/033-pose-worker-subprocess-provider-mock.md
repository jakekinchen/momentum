# Brief 033: Pose Worker Subprocess Provider Mock

## Objective

Add the smallest Swift-side subprocess provider boundary for `pose_worker/pose_worker.py` using deterministic `--mode mock`, then prove it can produce `PoseFrame` values through the existing JSONL decoder path. This moves M3 toward `MediaPipePoseProvider` spawning the worker while staying headless and offline.

## Scope

- Add a Swift app/engine boundary type that can launch the existing Python worker as a subprocess in `mock` mode.
- Send JSONL requests on stdin and read JSONL responses from stdout.
- Support at least:
  - a `health` request proving the worker is alive and pose-ready in mock mode;
  - a single `predict` request with deterministic timestamp/frame id;
  - decoding the returned `pose` line into `PoseFrame` using the existing `MediaPipePoseJSONLDecoder` shape.
- Keep lifecycle explicit: terminate/close the process after use, and surface failures as deterministic Swift errors.
- Add tests that run the worker in `--mode mock` only and validate the resulting `PoseFrame` reaches the app/session path or decoder path.

## Out Of Scope

- No live camera capture.
- No `mediapipe` worker mode.
- No model downloads.
- No `pip install` or Python environment mutation.
- No `pose_worker.py` changes unless a clear contract mismatch is found; if a worker change is required, stop and route it through reviewer/manager because pytest ownership changes.
- No SwiftUI app launch, screenshot, or visual verification claim.
- No long-running streaming/cancellation architecture beyond the minimal lifecycle needed for this slice.

## Acceptance Criteria

- Tests prove the Swift subprocess provider can launch `pose_worker.py --mode mock`, read a healthy response, request one deterministic pose, and decode it into a `PoseFrame`.
- Tests prove a provider failure path is deterministic, such as missing worker path or nonzero worker exit, without hanging.
- Tests prove the mock worker frame can feed either `AppExerciseSessionViewModel.runRecordedProvider(...)` or an equivalent app/session adapter path without using checked-in JSONL fixture files.
- The worker process is terminated/closed after the test path.
- Existing JSONL fixture provider, recorded-run catalog, HUD overlay, overlay view, and full Swift suite remain green.

## Expected Files

- `Sources/CamiFitEngine/PoseWorkerSubprocessProvider.swift` or a similarly named provider file.
- Optional small app adapter file only if needed.
- `Tests/CamiFitEngineTests/PoseWorkerSubprocessProviderTests.swift` or `Tests/CamiFitAppTests/...` if the app path owns the boundary.
- `docs/session-logs/033-executor-pose-worker-subprocess-provider-mock.md`.

## Validation

Run and record:

```sh
swift build --disable-sandbox
swift test --disable-sandbox --filter PoseWorkerSubprocessProviderTests
swift test --disable-sandbox
git diff --check
```

If the focused test name differs, record the exact command used.

Do not run or block on pytest unless this slice modifies `pose_worker/`; if that happens, stop and escalate for manager pytest handling.

## Session Log Requirements

In `docs/session-logs/033-executor-pose-worker-subprocess-provider-mock.md`, include:

- Files changed.
- Worker launch command used in tests.
- Focused and full validation commands with outcomes.
- Evidence of health response and decoded mock pose frame.
- Evidence of deterministic failure handling.
- Confirmation that no live camera, mediapipe mode, model download, `pip install`, or SwiftUI app-run verification was performed.
