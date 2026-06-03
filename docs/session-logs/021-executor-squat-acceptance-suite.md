# Executor Session Log 021 - Squat Acceptance Suite

Date: 2026-06-03 18:47:13 CDT

## Slice

Implemented the first explicit M1 bodyweight squat acceptance suite from `docs/briefs/021-squat-acceptance-suite.md`.

This slice stayed headless and offline. It did not spawn Python, open a camera, download a model, install packages, run the SwiftUI app, or claim live-app behavior.

## Files Changed

- `Tests/CamiFitEngineTests/SquatAcceptanceTests.swift`
  - Added fixture-driven acceptance coverage through the real squat preset and `EngineTraceRecorder`.
  - Covers clean, shallow / insufficient-ROM, low-visibility, and MediaPipe no-pose cases.
  - Asserts exact final rep counts, counted timestamps with explicit tolerance, invalid-interval no-false-count guarantees, and trace evidence text.
- `Tests/CamiFitEngineTests/Fixtures/synthetic_squat_shallow_trace.json`
  - Added a small nine-frame shallow squat fixture based on the existing shallow landmark shape used in rep-state tests.
- `docs/session-logs/021-executor-squat-acceptance-suite.md`
  - This log.

## Validation

Focused acceptance:

```bash
swift test --disable-sandbox --filter SquatAcceptanceTests
```

Result:

```text
Executed 1 test, with 0 failures (0 unexpected)
```

Focused evidence:

```text
squat-acceptance case=clean frames=17 expected_reps=1 actual_reps=1 expected_counted=[1600] actual_counted=[1600] tolerance_ms=50 invalid_interval=nil false_counts_invalid=0
squat-acceptance case=shallow frames=9 expected_reps=0 actual_reps=0 expected_counted=[] actual_counted=[] tolerance_ms=50 invalid_interval=nil false_counts_invalid=0
squat-acceptance case=low_visibility frames=5 expected_reps=0 actual_reps=0 expected_counted=[] actual_counted=[] tolerance_ms=50 invalid_interval=100...300 false_counts_invalid=0
squat-acceptance case=mediapipe_no_pose frames=3 expected_reps=0 actual_reps=0 expected_counted=[] actual_counted=[] tolerance_ms=50 invalid_interval=2100...2100 false_counts_invalid=0
```

Invalid trace evidence:

```text
100 | ready | 0 | false | knee=invalid(filter knee source knee_raw invalid: low confidence landmark primary.knee visibility=0.2 presence=1.0 threshold=0.65),knee_symmetry=valid(0.000, confidence: 1.000),torso_tilt=valid(0.000, confidence: 1.000) | form=none | cue=nil | score=nil | invalid=phase signal knee invalid: filter knee source knee_raw invalid: low confidence landmark primary.knee visibility=0.2 presence=1.0 threshold=0.65
2100 | ready | 0 | false | knee=invalid(filter knee source knee_raw invalid: missing landmark primary.hip),knee_symmetry=invalid(signal knee_left invalid: missing landmark left.hip),torso_tilt=invalid(filter torso_tilt source torso_raw invalid: missing landmark primary.shoulder) | form=none | cue=nil | score=nil | invalid=phase signal knee invalid: filter knee source knee_raw invalid: missing landmark primary.hip
```

Broad Swift:

```bash
swift build --disable-sandbox
swift test --disable-sandbox
```

Result:

```text
swift build --disable-sandbox: passed
swift test --disable-sandbox: Executed 65 tests, with 0 failures (0 unexpected)
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

Every acceptance case runs through the real product engine path:

```text
checked-in fixture
  -> PoseFrameFixtureLoader or MediaPipePoseProvider
  -> ProgramLoader.load(Presets/bodyweight_squat.json)
  -> EngineTraceRecorder.record(frames:)
  -> EngineTraceFormatter.format(_:)
```

No acceptance case asserts directly against `RepStateMachine`, `SignalEvaluator`, or hand-built output shortcuts.

## Evidence

Acceptance manifest:

```text
clean:
  fixture: synthetic_squat_clean_trace.json
  frames: 17
  expected rep count: 1
  actual rep count: 1
  expected counted timestamps: [1600]
  actual counted timestamps: [1600]
  tolerance: 50ms

shallow:
  fixture: synthetic_squat_shallow_trace.json
  frames: 9
  expected rep count: 0
  actual rep count: 0
  expected counted timestamps: []
  actual counted timestamps: []
  tolerance: 50ms

low_visibility:
  fixture: synthetic_squat_low_visibility_trace.json
  frames: 5
  expected rep count: 0
  actual rep count: 0
  invalid interval: 100...300
  false counts in invalid interval: 0
  evidence: low confidence landmark primary.knee

mediapipe_no_pose:
  fixture: mediapipe_pose_worker_mixed_no_pose.jsonl
  frames: 3
  expected rep count: 0
  actual rep count: 0
  invalid interval: 2100...2100
  false counts in invalid interval: 0
  evidence: missing landmark primary.hip
```

Fixture/tolerance choice:

- Counted timestamp tolerance is `50ms`, intentionally below the current fixture frame interval (`100ms`) so an off-by-one-frame count remains visible.
- The shallow fixture uses the existing shallow landmark geometry from `RepStateMachineTests` (`ankleXOffset: 0.153`, `ankleYOffset: 0.129`) so expectations are not a new product threshold decision.

## Flags For Reviewer

- This suite is a regression gate for M1 squat behavior, not a live camera/app proof.
- The acceptance suite reuses existing clean, low-visibility, and MediaPipe no-pose fixtures; only the small shallow fixture is new.
- The no-pose case uses `MediaPipePoseProvider` directly; the others use `PoseFrameFixtureLoader`.
- Python worker tests remain unavailable in the current environment because `pytest` is not installed.
- No live camera, app run, model download, Python process spawning, Layer 2, or Layer 3 behavior is included.

## Next Suggested Slice

Add a workflow/milestone verification gate for M1 that runs the squat acceptance suite alongside the existing build/test command, then have Reviewer decide whether M1 is complete enough to route toward the first macOS app wiring slice.
