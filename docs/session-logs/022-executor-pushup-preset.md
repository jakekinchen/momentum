# Executor Session Log 022 - Push-up Preset

Date: 2026-06-03 18:55:53 CDT

## Slice

Implemented the first M2 preset from `docs/briefs/022-pushup-preset.md`: a data-only bodyweight push-up preset with synthetic fixtures and an acceptance test.

This slice stayed pure Swift + JSON. It did not modify `Sources/CamiFitEngine/`, `pose_worker/`, the macOS app, network code, or download/install anything.

## Files Changed

- `Presets/bodyweight_pushup.json`
  - Added a hand-authored Exercise-Program for bodyweight push-ups.
  - Uses the existing contract: elbow angle phase signal, EMA filter, rep FSM thresholds, body-line and symmetry form rules, setup/validity/set blocks.
  - Avoids unsupported expression functions in the current evaluator.
- `Tests/CamiFitEngineTests/Fixtures/synthetic_pushup_clean_trace.json`
  - Added a 17-frame synthetic full push-up trace.
- `Tests/CamiFitEngineTests/Fixtures/synthetic_pushup_shallow_trace.json`
  - Added a 9-frame shallow/partial trace that must not count.
- `Tests/CamiFitEngineTests/PushupAcceptanceTests.swift`
  - Loads `bodyweight_pushup.json` through `ProgramLoader`.
  - Runs both fixtures through `PoseFrameFixtureLoader -> EngineTraceRecorder -> EngineTraceFormatter`.
  - Asserts clean exact final rep count and counted timestamp.
  - Asserts shallow exact final rep count `0`.
- `docs/session-logs/022-executor-pushup-preset.md`
  - This log.

## Validation

Focused push-up acceptance:

```bash
swift test --disable-sandbox --filter PushupAcceptanceTests
```

Result:

```text
Executed 1 test, with 0 failures (0 unexpected)
```

Focused evidence:

```text
pushup-acceptance case=clean frames=17 expected_reps=1 actual_reps=1 expected_counted=[1600] actual_counted=[1600] tolerance_ms=50
pushup-acceptance-trace-clean
1600 | ready | 1 | true | elbow=valid(169.991, confidence: 1.000) | form=none | cue=nil | score=nil | invalid=nil
pushup-acceptance case=shallow frames=9 expected_reps=0 actual_reps=0 expected_counted=[] actual_counted=[] tolerance_ms=50
```

Broad Swift:

```bash
swift build --disable-sandbox
swift test --disable-sandbox
```

Result:

```text
swift build --disable-sandbox: passed
swift test --disable-sandbox: Executed 66 tests, with 0 failures (0 unexpected)
```

The broad `swift test` waited for the concurrent `swift build` lock and then completed successfully.

Python worker tests:

- Not run. This slice does not modify `pose_worker/`, and `GOAL.md` says slices that do not modify `pose_worker/` validate with `swift test --disable-sandbox` only and must not block on pytest.

## Reachability

Real product path proven headlessly:

```text
Presets/bodyweight_pushup.json
Tests/CamiFitEngineTests/Fixtures/synthetic_pushup_clean_trace.json
Tests/CamiFitEngineTests/Fixtures/synthetic_pushup_shallow_trace.json
  -> PoseFrameFixtureLoader
  -> ProgramLoader.load(Presets/bodyweight_pushup.json)
  -> EngineTraceRecorder.record(frames:)
  -> EngineTraceFormatter.format(_:)
```

No acceptance assertion bypasses the product path with direct `RepStateMachine` or `SignalEvaluator` shortcuts.

## Evidence

Acceptance manifest:

```text
clean:
  fixture: synthetic_pushup_clean_trace.json
  frames: 17
  expected rep count: 1
  actual rep count: 1
  expected counted timestamps: [1600]
  actual counted timestamps: [1600]
  tolerance: 50ms

shallow:
  fixture: synthetic_pushup_shallow_trace.json
  frames: 9
  expected rep count: 0
  actual rep count: 0
  expected counted timestamps: []
  actual counted timestamps: []
  tolerance: 50ms
```

Fixture / preset choices:

- The clean fixture mirrors the squat acceptance timing shape: top hold, bottom hold, return to top, counted at `1600ms`.
- The shallow fixture moves but never crosses the push-up `down_when` threshold.
- The preset uses `primary.elbow` as the phase signal. It also computes left/right elbow symmetry for form evidence, but it does not use `min()` because the current Swift evaluator does not implement `min()` / `max()` even though they are mentioned in the broader design examples.

## Flags For Reviewer

- No engine source files changed. If later exercises require `min()` / `max()` or richer body-line geometry, that should be a separate contract/evaluator slice.
- Push-up form rules are intentionally minimal acceptance coverage, not a coaching-accuracy claim.
- The current `EngineTraceRecorder` selected-produced-value display is squat-biased but still includes the push-up phase signal (`elbow`), so trace reachability is visible without changing engine code.
- This slice relies only on Swift validation per the updated `GOAL.md` pytest-gate rule.

## Next Suggested Slice

Add a lunge preset as the next M2 data-only exercise, reusing the push-up acceptance pattern: preset JSON, clean/shallow fixtures, and a focused acceptance test with no engine changes unless a real contract gap appears.
