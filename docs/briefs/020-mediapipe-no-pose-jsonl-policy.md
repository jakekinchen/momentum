# Slice Brief 020 - MediaPipe No-Pose JSONL Policy

**Date:** 2026-06-03

## Objective

Extend the headless Swift MediaPipe JSONL decode boundary to handle valid `pose_worker` no-pose records.

Policy for this slice: a record with `poses_detected:0`, `primary_pose_id:null`, and empty `landmarks` / `world_landmarks` must decode to a timestamped `PoseFrame` with image dimensions preserved and `landmarks == [:]`. The engine should then record invalid/missing signal evidence and count no false reps.

Do not filter no-pose frames out at the provider layer.

## Product / Project Value

The worker schema explicitly emits no-pose frames. M1 requires no false counted reps during no-person / low-visibility intervals, and the live app will need timeline continuity. Preserving no-pose frames as empty-landmark `PoseFrame` values lets the deterministic engine, not the provider, own invalid evidence and rep safety.

## Scope

- Add a small checked-in JSONL fixture under `Tests/CamiFitEngineTests/Fixtures/` containing:
  - at least one valid pose frame with 33 landmarks;
  - at least one valid no-pose frame with `poses_detected:0`, `primary_pose_id:null`, `landmarks:[]`, and `world_landmarks:[]`;
  - another valid pose frame after the no-pose interval if useful for proving timeline continuity.
- Update the Swift MediaPipe decoder/provider to:
  - decode no-pose records to empty-landmark `PoseFrame` values;
  - preserve timestamp and image dimensions;
  - continue to require exactly 33 landmarks when `poses_detected >= 1`;
  - continue to fail malformed or inconsistent records.
- Add focused tests proving no-pose frames run through `EngineTraceRecorder` and `EngineTraceFormatter` with invalid/missing signal evidence and no counted reps during the no-pose interval.
- Keep the slice headless and offline.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass using the default in-repo `.build`.
- Focused tests prove:
  - no-pose JSONL records decode to `PoseFrame` values rather than being dropped;
  - decoded no-pose frames preserve `timestampMS`, `imageWidth`, and `imageHeight`;
  - decoded no-pose frames have no landmarks;
  - a mixed pose/no-pose/pose fixture preserves frame order;
  - trace output for no-pose frames includes invalid/missing signal evidence;
  - no frame in the no-pose interval has `countedThisFrame == true`;
  - final rep count remains explicitly asserted for the mixed fixture.
- Existing MediaPipe pose decode tests remain green.
- Existing low-visibility fixture tests remain green.
- No Python process is spawned.
- No model download, camera access, SwiftUI app run, network dependency, Layer 2, or Layer 3 behavior is added.

## Expected Files

Likely files include:

- `Sources/CamiFitEngine/MediaPipePoseProvider.swift`
- A small JSONL fixture under `Tests/CamiFitEngineTests/Fixtures/`
- `Tests/CamiFitEngineTests/MediaPipePoseProviderTests.swift`
- `docs/session-logs/020-executor-mediapipe-no-pose-jsonl-policy.md`

Names may change if the existing codebase has a clearer local structure. Keep the no-pose policy explicit.

## Validation Commands

```bash
cd /Users/kelly/Developer/camifit
swift build --disable-sandbox
swift test --disable-sandbox
```

Do not attempt `pip install`. If Python worker tests cannot run because `pytest` is unavailable, record that fact and continue with Swift validation.

## Evidence To Record

- `swift build --disable-sandbox` result.
- `swift test --disable-sandbox` test count and pass/fail.
- Decoded mixed fixture summary: frame count, timestamps, no-pose timestamps, dimensions.
- Trace excerpt for no-pose frames showing invalid/missing signal evidence.
- No-false-count evidence for the no-pose interval.
- Proof that malformed inconsistent records still fail.

## Reachability / Demo Proof

A test must load the checked-in mixed JSONL fixture, decode it through `MediaPipePoseProvider` / `MediaPipePoseJSONLDecoder`, produce `[PoseFrame]`, and run those frames through `EngineTraceRecorder` and `EngineTraceFormatter`.

Do not prove this only with hand-built `PoseFrame` values.

## Out Of Scope

- Spawning `pose_worker.py`.
- Downloading or bundling a MediaPipe model.
- Camera capture.
- Live SwiftUI app wiring or visual overlay verification.
- Audio, transport, replay UI, plotting, Layer 2, Layer 3, or persistence.
- Large recorded datasets or binary assets.
- Changing the primary-side alias policy unless needed for a no-pose bug.
- Broad exercise-engine semantic changes unrelated to no-pose decode behavior.

## Stop Conditions

- ESCALATE before adding any network access, model download, `pip install`, camera code, live app run, or Python process spawning.
- ESCALATE if preserving no-pose frames as empty-landmark `PoseFrame` values conflicts with existing engine invariants in a way that needs a human product choice.
- STOP if `swift test --disable-sandbox` cannot run with the default in-repo `.build`; record the exact failure.
- Do not claim the live camera or app works from this slice. This slice proves no-pose decode and engine reachability only.
