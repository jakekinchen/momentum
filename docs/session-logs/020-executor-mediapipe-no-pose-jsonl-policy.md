# Executor Session Log 020 - MediaPipe No-Pose JSONL Policy

Date: 2026-06-03 18:41:17 CDT

## Slice

Implemented the no-pose JSONL policy from `docs/briefs/020-mediapipe-no-pose-jsonl-policy.md`.

Policy implemented: valid `pose_worker` no-pose records decode to timestamped `PoseFrame` values with preserved dimensions and `landmarks == [:]`. No-pose frames are not filtered at the provider layer.

This slice stayed headless and offline. It did not spawn Python, open a camera, download a model, install packages, run the SwiftUI app, or claim live-app behavior.

## Files Changed

- `Sources/CamiFitEngine/MediaPipePoseProvider.swift`
  - Added `poses_detected`, `primary_pose_id`, and `world_landmarks` decoding.
  - Decodes `poses_detected:0`, `primary_pose_id:null`, `landmarks:[]`, `world_landmarks:[]` to an empty-landmark `PoseFrame`.
  - Continues to require exactly 33 landmarks when `poses_detected > 0`.
  - Fails closed for negative `poses_detected` and inconsistent no-pose records.
- `Tests/CamiFitEngineTests/Fixtures/mediapipe_pose_worker_mixed_no_pose.jsonl`
  - Added a pose / no-pose / pose fixture with timestamps `2000`, `2100`, `2200`.
- `Tests/CamiFitEngineTests/MediaPipePoseProviderTests.swift`
  - Added mixed no-pose fixture decode and trace reachability test.
  - Added inconsistent no-pose fail-closed test.
  - Updated inline JSON snippets to include worker contract fields.
- `docs/session-logs/020-executor-mediapipe-no-pose-jsonl-policy.md`
  - This log.

## Validation

Focused Swift:

```bash
swift test --disable-sandbox --filter MediaPipePoseProviderTests
```

Result:

```text
Executed 6 tests, with 0 failures (0 unexpected)
```

Focused evidence:

```text
mediapipe-jsonl-no-pose frames=3 timestamps=[2000, 2100, 2200] no_pose=[2100] size=1280.0x720.0 counted_in_no_pose=0 final_reps=0
mediapipe-jsonl-no-pose-trace
2100 | ready | 0 | false | knee=invalid(filter knee source knee_raw invalid: missing landmark primary.hip),knee_symmetry=invalid(signal knee_left invalid: missing landmark left.hip),torso_tilt=invalid(filter torso_tilt source torso_raw invalid: missing landmark primary.shoulder) | form=none | cue=nil | score=nil | invalid=phase signal knee invalid: filter knee source knee_raw invalid: missing landmark primary.hip
mediapipe-jsonl-no-pose-inconsistent fail_closed=true
```

Broad Swift:

```bash
swift build --disable-sandbox
swift test --disable-sandbox
```

Result:

```text
swift build --disable-sandbox: passed
swift test --disable-sandbox: Executed 64 tests, with 0 failures (0 unexpected)
```

Pose worker Python tests:

```bash
python3 -m pytest pose_worker/tests -q
```

Result:

```text
/opt/homebrew/opt/python@3.14/bin/python3.14: No module named pytest
```

No install was attempted because the active brief explicitly says not to attempt `pip install`.

## Reachability

Real product path proven headlessly:

```text
Tests/CamiFitEngineTests/Fixtures/mediapipe_pose_worker_mixed_no_pose.jsonl
  -> MediaPipePoseProvider(jsonlURL:)
  -> MediaPipePoseJSONLDecoder
  -> [PoseFrame]
  -> ProgramLoader.load(Presets/bodyweight_squat.json)
  -> EngineTraceRecorder.record(frames:)
  -> EngineTraceFormatter.format(_:)
```

The no-pose frame remains in the timeline as timestamp `2100`, reaches the engine as `landmarks == [:]`, and produces invalid/missing-signal trace evidence.

## Evidence

- Mixed fixture frame count: `3`
- Decoded timestamps: `[2000, 2100, 2200]`
- No-pose timestamp: `2100`
- No-pose dimensions: `1280.0x720.0`
- No-pose landmarks: `[:]`
- No-pose interval false counts: `0`
- Final rep count for mixed fixture: `0`
- Trace invalid evidence includes:
  - `missing landmark primary.hip`
  - `missing landmark left.hip`
  - `missing landmark primary.shoulder`
- Inconsistent no-pose failure proof: `poses_detected:0` with non-null `primary_pose_id` throws an error containing `no-pose record must have null primary_pose_id`.

## Flags For Reviewer

- The no-pose policy is now explicit in Swift: preserve no-pose timeline frames as empty-landmark `PoseFrame` values and let the engine own invalid evidence and rep safety.
- Positive `poses_detected` records still require exactly 33 landmarks.
- This slice makes `poses_detected`, `primary_pose_id`, and `world_landmarks` required fields for decoded worker records. That matches the documented worker schema and keeps malformed records fail-closed.
- Python worker tests remain unavailable in the current environment because `pytest` is not installed.
- No live camera, app run, model download, Python process spawning, Layer 2, or Layer 3 behavior is included.

## Next Suggested Slice

Add a small `MediaPipePoseProvider` process-request/response abstraction that can be tested with an in-memory line source/sink, without spawning Python. The goal should be validating JSONL request/response framing and error surfacing before any real `pose_worker.py` process management.
