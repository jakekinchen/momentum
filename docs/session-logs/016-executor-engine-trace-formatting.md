# Executor Session 016 - Engine Trace Formatting

**Date:** 2026-06-03  
**Role:** Executor  
**Active brief:** `docs/briefs/016-engine-trace-formatting.md`

## Slice Summary

Added deterministic in-memory text formatting for engine trace frames:

- `EngineTraceFormatter.format(_:)` converts `[EngineTraceFrame]` to stable pipe-separated text.
- The formatter emits a fixed header and one row per trace frame.
- Rows include timestamp, rep phase, rep count, counted flag, selected produced values, active form rule summaries, selected cue, score, and invalid reason.
- Produced values use the deterministic order already captured by `EngineTraceRecorder`.
- Formatting stays string-only; there is no file export, JSON schema, UI, plotting, camera, Python, or network behavior.

This slice did not change trace recording, evaluator, FSM, form-rule, cooldown, or scoring semantics.

## Files Changed

- `Sources/CamiFitEngine/EngineTraceRecorder.swift`
- `Tests/CamiFitEngineTests/EngineTraceRecorderTests.swift`
- `docs/session-logs/016-executor-engine-trace-formatting.md`

## Validation

Startup workflow audit:

```bash
scripts/audit_autonomous_workflow.sh
```

Result before implementation: clean.

Focused red check before production code:

```bash
swift test --disable-sandbox --filter EngineTraceRecorderTests
```

Result: failed as expected because the new tests referenced the missing formatter boundary:

- `cannot find 'EngineTraceFormatter' in scope`

Focused validation after implementation:

```bash
swift test --disable-sandbox --filter EngineTraceRecorderTests
```

Result:

- 7 tests executed.
- 0 failures.

Focused evidence:

```text
engine-trace-format-deterministic
timestamp_ms | phase | reps | counted | produced | form | cue | score | invalid
0 | ready | 0 | false | knee=valid(180.000, confidence: 1.000),knee_symmetry=valid(0.000, confidence: 1.000),torso_tilt=valid(0.000, confidence: 1.000) | form=none | cue=nil | score=nil | invalid=nil
100 | ready | 0 | false | knee=valid(148.500, confidence: 1.000),knee_symmetry=valid(0.000, confidence: 1.000),torso_tilt=valid(0.000, confidence: 1.000) | form=none | cue=nil | score=nil | invalid=nil
200 | ready | 0 | false | knee=valid(128.025, confidence: 1.000),knee_symmetry=valid(0.000, confidence: 1.000),torso_tilt=valid(0.000, confidence: 1.000) | form=none | cue=nil | score=nil | invalid=nil
300 | ready | 0 | false | knee=valid(114.716, confidence: 1.000),knee_symmetry=valid(0.000, confidence: 1.000),torso_tilt=valid(0.000, confidence: 1.000) | form=none | cue=nil | score=nil | invalid=nil
engine-trace-format-counted
1600 | ready | 1 | true | knee=valid(173.304, confidence: 1.000),knee_symmetry=valid(0.000, confidence: 1.000),torso_tilt=valid(0.000, confidence: 1.000) | form=none | cue=nil | score=nil | invalid=nil
engine-trace-format-invalid
timestamp_ms | phase | reps | counted | produced | form | cue | score | invalid
0 | seeking_ready | 0 | false | knee=invalid(filter knee source knee_raw invalid: low confidence landmark primary.knee visibility=0.2 presence=1.0 threshold=0.65),knee_symmetry=valid(0.000, confidence: 1.000),torso_tilt=valid(0.000, confidence: 1.000) | form=none | cue=nil | score=nil | invalid=phase signal knee invalid: filter knee source knee_raw invalid: low confidence landmark primary.knee visibility=0.2 presence=1.0 threshold=0.65
```

Broad validation:

```bash
swift build --disable-sandbox
swift test --disable-sandbox
```

Result:

- Build completed successfully.
- Full test suite executed 55 tests with 0 failures.

## Reachability Proof

`EngineTraceRecorderTests` proves formatting from the real loaded squat preset:

1. `ProgramLoader` loads `Presets/bodyweight_squat.json`.
2. `EngineTraceRecorder` records synthetic timestamped squat frames through `FrameSignalProcessor`, `RepPredicateEvaluator`, `RepStateMachine`, `FormRuleEvaluator`, and `FormRuleScoreSummarizer`.
3. The resulting real `EngineTraceFrame` values are passed to `EngineTraceFormatter.format`.
4. Tests assert deterministic repeated formatting, counted-rep visibility, selected produced values, active form-rule text, score fields, and invalid reason fields.

The invalid-frame formatting test uses the same loaded preset and recorder path with a low-visibility `primary.knee`, proving the formatted output retains both invalid produced value text and the rep invalid reason.

## Flags For Reviewer

- The formatter is intentionally plain text only. File export, JSON schema, replay UI, plotting, recorded fixtures, and live UI are out of scope.
- Rows use `form=none` when no form rules are active on that frame; bottom frames still carry active form rule summaries and score output.
- Counted-rep frames may have no active form rules under the current squat phase semantics; the formatted counted row correctly shows `form=none` and `score=nil`.
- No Python, MediaPipe, camera, network access, package dependencies, Layer 2, or Layer 3 behavior was added.

## Next Suggested Slice

Add the smallest recorded-fixture harness slice: define a repo-local fixture container for deterministic `PoseFrame` sequences and run the existing trace recorder/formatter against one checked-in synthetic squat fixture, without MediaPipe, camera, UI, plotting, or no-person acceptance gates yet.
