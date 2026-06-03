# Slice Brief 019 - MediaPipe PoseProvider JSONL Decode

**Date:** 2026-06-03

## Objective

Add the smallest Swift `MediaPipePoseProvider` decode slice: parse a recorded `pose_worker` JSONL fixture into named `PoseFrame` values behind the Swift pose-provider boundary.

Keep this headless and offline. Do not spawn Python, download a model, open a camera, run the SwiftUI app, or claim live app behavior.

## Product / Project Value

The MediaPipe pose worker now exists at `pose_worker/`. M1 needs a deterministic bridge from that worker's timestamped landmark output into the Swift exercise engine before any live camera/app verification can be meaningful.

This slice proves the worker-output schema can become engine-ready `PoseFrame` values with correct landmark naming, dimensions, timestamps, and confidence values.

## Scope

- Read the existing `pose_worker/` code and any tests/docs to identify the real JSONL output schema.
- Add or confirm a minimal Swift pose-provider boundary if one is not already present.
- Add a small checked-in JSONL fixture under `Tests/CamiFitEngineTests/Fixtures/` that matches the `pose_worker` output shape.
- Decode ordered MediaPipe pose landmarks into engine landmark names needed by the current squat preset, including `primary.*` and left/right aliases where appropriate.
- Preserve:
  - `timestampMS`;
  - image width/height;
  - landmark `x`, `y`, `z`;
  - `visibility`;
  - `presence` when present, with a documented fallback if the worker schema omits it.
- Fail closed on malformed JSON lines, missing frame fields, wrong landmark count, or missing required landmark mappings.
- Run decoded frames through `EngineTraceRecorder` and `EngineTraceFormatter` with `Presets/bodyweight_squat.json`.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass using the default in-repo `.build`.
- Focused tests prove:
  - the JSONL fixture decodes to the expected frame count;
  - decoded frame timestamps and image dimensions match the fixture;
  - ordered MediaPipe landmarks map to expected engine names such as `primary.hip`, `primary.knee`, `primary.ankle`, and `primary.shoulder`;
  - left/right named landmarks are available where the mapping supports them;
  - visibility and presence/confidence values are preserved or explicitly defaulted according to the decoder contract;
  - malformed JSONL and wrong landmark counts fail with a clear error;
  - decoded frames can run through the existing trace recorder/formatter path.
- No Python process is spawned.
- No model download, camera access, SwiftUI app run, network dependency, Layer 2, or Layer 3 behavior is added.

## Expected Files

Likely files include:

- Swift source for the provider/decoder boundary, for example under `Sources/CamiFitEngine/`.
- A small JSONL fixture under `Tests/CamiFitEngineTests/Fixtures/`.
- Focused tests, for example `Tests/CamiFitEngineTests/MediaPipePoseProviderTests.swift`.
- `docs/session-logs/019-executor-mediapipe-poseprovider-jsonl-decode.md`

Names may change if the existing codebase has a clearer local structure. Keep the boundary explicit and avoid mixing this with live app or process-management work.

## Validation Commands

```bash
cd /Users/kelly/Developer/camifit
swift build --disable-sandbox
swift test --disable-sandbox
```

If Python tests already exist for `pose_worker/` and can run without downloads or environment setup, run them and record the result. If they cannot run in-scope, record the concrete reason and continue with Swift validation.

## Evidence To Record

- `swift build --disable-sandbox` result.
- `swift test --disable-sandbox` test count and pass/fail.
- Decoded fixture summary: frame count, timestamps, dimensions.
- Landmark mapping proof for at least hip/knee/ankle/shoulder.
- Visibility/presence preservation proof.
- Malformed JSONL or wrong-landmark-count failure proof.
- Trace recorder/formatter reachability proof using decoded frames.

## Reachability / Demo Proof

A test must load the checked-in JSONL fixture, decode it through the new MediaPipe provider/decoder boundary, produce `[PoseFrame]`, and run those frames through `EngineTraceRecorder` and `EngineTraceFormatter`.

Do not prove this only with hand-built `PoseFrame` values.

## Out Of Scope

- Spawning `pose_worker.py`.
- Downloading or bundling a MediaPipe model.
- Camera capture.
- Live SwiftUI app wiring or visual overlay verification.
- Audio, transport, replay UI, plotting, Layer 2, Layer 3, or persistence.
- Large recorded datasets or binary assets.
- Broad exercise-engine semantic changes unrelated to decoding worker output.

## Stop Conditions

- ESCALATE before adding any network access, model download, `pip install`, camera code, live app run, or Python process spawning.
- ESCALATE if the real `pose_worker` JSONL schema is ambiguous enough that a human choice is needed.
- STOP if `swift test --disable-sandbox` cannot run with the default in-repo `.build`; record the exact failure.
- Do not claim the live camera or app works from this slice. This slice proves decode and engine reachability only.
