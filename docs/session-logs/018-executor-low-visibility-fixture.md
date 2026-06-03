# Executor Session 018 - Low-Visibility Fixture

**Date:** 2026-06-03  
**Role:** Executor  
**Active brief:** `docs/briefs/018-low-visibility-fixture.md`

## Slice Summary

Added a second small checked-in synthetic fixture for low-visibility/no-person-style invalid pose intervals:

- Added `Tests/CamiFitEngineTests/Fixtures/synthetic_squat_low_visibility_trace.json`.
- Extended `PoseFrameFixtureTests` to load the low-visibility fixture through `PoseFrameFixtureLoader`.
- Ran the loaded fixture through `EngineTraceRecorder` and `EngineTraceFormatter`.
- Asserted invalid `knee` produced values and rep invalid reasons are retained.
- Asserted no frame in the low-visibility interval counts a rep and the final rep count remains `0`.

This is a deterministic fixture case only. It does not claim coaching accuracy or complete the full no-person/low-visibility golden gate.

## Files Changed

- `Tests/CamiFitEngineTests/Fixtures/synthetic_squat_low_visibility_trace.json`
- `Tests/CamiFitEngineTests/PoseFrameFixtureTests.swift`
- `docs/session-logs/018-executor-low-visibility-fixture.md`

## Validation

Startup workflow audit:

```bash
scripts/audit_autonomous_workflow.sh
```

Result before implementation: clean.

Focused red check before fixture creation:

```bash
swift test --disable-sandbox --filter PoseFrameFixtureTests/testLowVisibilityFixtureRecordsInvalidEvidenceWithoutFalseCounts
```

Result: failed as expected because the new test referenced the missing checked-in fixture:

- `The file “synthetic_squat_low_visibility_trace.json” couldn’t be opened because there is no such file.`

Focused validation after fixture creation:

```bash
swift test --disable-sandbox --filter PoseFrameFixtureTests/testLowVisibilityFixtureRecordsInvalidEvidenceWithoutFalseCounts
swift test --disable-sandbox --filter PoseFrameFixtureTests
```

Result:

- Low-visibility focused test: 1 test executed, 0 failures.
- Fixture test file: 3 tests executed, 0 failures.

Focused evidence:

```text
pose-fixture-low-visibility frames=5 invalid=[100, 200, 300] counted_in_invalid=0 final_reps=0
pose-fixture-low-visibility-invalid
100 | ready | 0 | false | knee=invalid(filter knee source knee_raw invalid: low confidence landmark primary.knee visibility=0.2 presence=1.0 threshold=0.65),knee_symmetry=valid(0.000, confidence: 1.000),torso_tilt=valid(0.000, confidence: 1.000) | form=none | cue=nil | score=nil | invalid=phase signal knee invalid: filter knee source knee_raw invalid: low confidence landmark primary.knee visibility=0.2 presence=1.0 threshold=0.65
200 | ready | 0 | false | knee=invalid(filter knee source knee_raw invalid: low confidence landmark primary.knee visibility=0.2 presence=1.0 threshold=0.65),knee_symmetry=valid(0.000, confidence: 1.000),torso_tilt=valid(0.000, confidence: 1.000) | form=none | cue=nil | score=nil | invalid=phase signal knee invalid: filter knee source knee_raw invalid: low confidence landmark primary.knee visibility=0.2 presence=1.0 threshold=0.65
300 | ready | 0 | false | knee=invalid(filter knee source knee_raw invalid: low confidence landmark primary.knee visibility=0.2 presence=1.0 threshold=0.65),knee_symmetry=valid(0.000, confidence: 1.000),torso_tilt=valid(0.000, confidence: 1.000) | form=none | cue=nil | score=nil | invalid=phase signal knee invalid: filter knee source knee_raw invalid: low confidence landmark primary.knee visibility=0.2 presence=1.0 threshold=0.65
```

Broad validation:

```bash
swift build --disable-sandbox
swift test --disable-sandbox
```

Result:

- Build completed successfully.
- Full test suite executed 58 tests with 0 failures.

## Reachability Proof

`PoseFrameFixtureTests.testLowVisibilityFixtureRecordsInvalidEvidenceWithoutFalseCounts` proves the low-visibility fixture path through the real engine:

1. Load `Tests/CamiFitEngineTests/Fixtures/synthetic_squat_low_visibility_trace.json`.
2. Convert fixture frames into `[PoseFrame]` with `PoseFrameFixtureLoader`.
3. Load the real preset `Presets/bodyweight_squat.json`.
4. Run fixture frames through `EngineTraceRecorder`, which uses `FrameSignalProcessor`, `RepPredicateEvaluator`, `RepStateMachine`, `FormRuleEvaluator`, and `FormRuleScoreSummarizer`.
5. Format the resulting trace with `EngineTraceFormatter`.
6. Assert the low-visibility interval at 100ms, 200ms, and 300ms records invalid `knee` output and rep invalid reasons, with no counted reps during that interval and final rep count `0`.

## Flags For Reviewer

- This is still a small synthetic fixture, not a real recorded MediaPipe fixture and not the full no-person/low-visibility acceptance suite.
- The fixture intentionally covers an invalid interval only and expects zero reps overall.
- The test asserts invalid produced value retention and no false counted reps through the trace/formatter path; it does not change engine semantics.
- No Python, MediaPipe, camera, network access, package dependencies, large recordings, Layer 2, or Layer 3 behavior was added.

## Next Suggested Slice

Add the smallest `MediaPipePoseProvider` decode slice: decode a recorded pose-worker JSONL fixture into named `PoseFrame` values behind the Swift `PoseProvider` boundary, without spawning Python, downloading models, using camera, or claiming live app behavior.
