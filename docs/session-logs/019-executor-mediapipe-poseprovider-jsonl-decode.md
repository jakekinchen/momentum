# Executor Session Log 019 - MediaPipe PoseProvider JSONL Decode

Date: 2026-06-03 18:35:36 CDT

## Slice

Implemented the smallest headless/offline MediaPipe pose-provider decode slice from `docs/briefs/019-mediapipe-poseprovider-jsonl-decode.md`.

This slice does not spawn Python, open a camera, download a model, install packages, run the SwiftUI app, or claim live-app behavior.

## Files Changed

- `Sources/CamiFitEngine/MediaPipePoseProvider.swift`
  - Added `PoseProvider` boundary.
  - Added `MediaPipePoseProvider(jsonlURL:)`.
  - Added `MediaPipePoseJSONLDecoder` for line-delimited `pose_worker` records.
  - Maps MediaPipe's ordered 33 landmarks to engine names such as `left.knee`, `right.knee`, and `primary.knee`.
  - Preserves `timestamp_ms`, `image_size`, `x/y/z`, `visibility`, and `presence`.
  - Defaults missing `presence` to `visibility`.
  - Fails closed on malformed JSON, non-`pose` records, malformed `image_size`, and wrong landmark counts.
- `Tests/CamiFitEngineTests/Fixtures/mediapipe_pose_worker_two_frames.jsonl`
  - Two checked-in `pose_worker`-shaped JSONL frames with exactly 33 ordered landmarks.
- `Tests/CamiFitEngineTests/MediaPipePoseProviderTests.swift`
  - Focused decode tests.
  - Fail-closed malformed JSONL / wrong landmark count tests.
  - Presence fallback test.
  - Product reachability test through `EngineTraceRecorder` and `EngineTraceFormatter`.
- `docs/session-logs/019-executor-mediapipe-poseprovider-jsonl-decode.md`
  - This log.

## Validation

Focused Swift:

```bash
swift test --disable-sandbox --filter MediaPipePoseProviderTests
```

Result:

```text
Executed 4 tests, with 0 failures (0 unexpected)
```

Focused evidence:

```text
mediapipe-jsonl-decode frames=2 timestamps=[1000, 1100] size=1280.0x720.0 primary_knee=Optional(CamiFitEngine.PoseLandmark(x: 0.65, y: 0.64, z: -0.01, visibility: 0.96, presence: 0.97))
mediapipe-jsonl-presence-fallback right_knee_presence=0.96
mediapipe-jsonl-fail-closed malformed=true wrong_count=true
mediapipe-jsonl-trace frames=2 trace=2
timestamp_ms | phase | reps | counted | produced | form | cue | score | invalid
1000 | ready | 0 | false | knee=valid(180.000, confidence: 0.950),knee_symmetry=valid(0.000, confidence: 0.880),torso_tilt=valid(0.000, confidence: 0.970) | form=none | cue=nil | score=nil | invalid=nil
1100 | ready | 0 | false | knee=valid(180.000, confidence: 0.950),knee_symmetry=valid(0.000, confidence: 0.880),torso_tilt=valid(0.000, confidence: 0.970) | form=none | cue=nil | score=nil | invalid=nil
```

Broad Swift:

```bash
swift build --disable-sandbox
swift test --disable-sandbox
```

Result:

```text
swift build --disable-sandbox: passed
swift test --disable-sandbox: Executed 62 tests, with 0 failures (0 unexpected)
```

Pose worker Python tests:

```bash
python3 -m pytest pose_worker/tests -q
```

Result:

```text
/opt/homebrew/opt/python@3.14/bin/python3.14: No module named pytest
```

No install was attempted because the active brief forbids `pip install` without authorization.

## Reachability

Real product path proven headlessly:

```text
Tests/CamiFitEngineTests/Fixtures/mediapipe_pose_worker_two_frames.jsonl
  -> MediaPipePoseProvider(jsonlURL:)
  -> MediaPipePoseJSONLDecoder
  -> [PoseFrame]
  -> ProgramLoader.load(Presets/bodyweight_squat.json)
  -> EngineTraceRecorder.record(frames:)
  -> EngineTraceFormatter.format(_:)
```

The reachability proof uses decoded worker-shaped JSONL frames, not hand-built `PoseFrame` values.

## Evidence

- Fixture frame count: `2`
- Decoded timestamps: `[1000, 1100]`
- Decoded dimensions: `1280.0x720.0`
- Landmark mapping proof:
  - `right.shoulder = x:0.65 y:0.24 z:-0.01 visibility:0.98 presence:0.99`
  - `right.hip = x:0.65 y:0.44 z:-0.01 visibility:0.97 presence:0.98`
  - `right.knee = x:0.65 y:0.64 z:-0.01 visibility:0.96 presence:0.97`
  - `right.ankle = x:0.65 y:0.84 z:-0.01 visibility:0.95 presence:0.96`
  - `primary.*` maps to the stronger right-side landmarks for this fixture.
- Presence fallback proof: omitted `presence` decodes as `presence == visibility`.
- Malformed JSONL failure proof: malformed JSON throws a decode error containing `malformed JSON`.
- Wrong landmark count proof: zero landmarks throws a decode error containing `expected 33 landmarks, got 0`.
- Trace proof: decoded frames produce valid `knee`, `knee_symmetry`, and `torso_tilt` rows through the existing squat preset.

## Flags For Reviewer

- The primary alias policy is deterministic but intentionally minimal: choose the side with the highest mean confidence across shoulder/hip/knee/ankle, tie-breaking to right. Please confirm this is acceptable for the first provider boundary.
- `presence` fallback is `presence = visibility` when omitted. The current worker schema includes presence, but the test documents the fallback.
- Python worker tests were not run because `pytest` is not installed in the active Python. No package install was attempted.
- No live camera, app run, model download, Python process spawning, Layer 2, or Layer 3 behavior is included.

## Next Suggested Slice

Add a process-free `MediaPipePoseProvider` no-pose JSONL decode fixture and tests for `poses_detected:0` policy, then decide whether no-pose should decode to an empty-landmark `PoseFrame` or be filtered before engine ingestion. Keep it headless and avoid spawning Python.
