# Executor Session 003 - PoseFrame + Core Signal Evaluator

Date: 2026-06-03
Role: Executor
Brief: `docs/briefs/003-poseframe-signal-evaluator-core.md`
Slice: core runtime evaluator for the squat preset's raw numeric signals.

## Slice

Implemented the first runtime evaluation increment:

- Added `PoseFrame` and `PoseLandmark` value types with timestamp, image dimensions, and named landmark lookup.
- Added `SignalValue.valid(value:confidence:)` / `SignalValue.invalid(reason:)`.
- Added a small expression lexer/parser/AST/evaluator for this slice's numeric subset:
  - numeric literals;
  - signal references;
  - landmark references;
  - `+`, `-`, `*`, `/` with safe divide;
  - `angle`, `angle_to_vertical`, and `abs`.
- Added `SignalEvaluator` to parse program raw `signals`, evaluate them in dependency order, and apply `validity.min_signal_confidence`.
- Added tests that load the real squat preset, evaluate a synthetic standing pose, prove deterministic output, prove low-visibility invalidation, and prove divide-by-zero / degenerate geometry return invalid values.

## Files Changed

- `Sources/CamiFitEngine/PoseFrame.swift`
- `Sources/CamiFitEngine/SignalValue.swift`
- `Sources/CamiFitEngine/Expression/AST.swift`
- `Sources/CamiFitEngine/Expression/Lexer.swift`
- `Sources/CamiFitEngine/Expression/Parser.swift`
- `Sources/CamiFitEngine/Expression/Evaluator.swift`
- `Sources/CamiFitEngine/SignalEvaluator.swift`
- `Tests/CamiFitEngineTests/SignalEvaluatorTests.swift`
- `docs/session-logs/003-executor-poseframe-signal-evaluator-core.md`

## Validation

Startup audit:

```text
git status --short --branch
## main

scripts/audit_autonomous_workflow.sh
workflow audit clean
```

Test-first red run:

```text
swift test --disable-sandbox --filter SignalEvaluatorTests

SignalEvaluatorTests.swift:69:32: error: cannot find type 'PoseFrame' in scope
SignalEvaluatorTests.swift:91:18: error: cannot find type 'SignalValue' in scope
SignalEvaluatorTests.swift:7:29: error: cannot find 'SignalEvaluator' in scope
```

Focused validation:

```text
swift test --disable-sandbox --filter SignalEvaluatorTests

Test Suite 'SignalEvaluatorTests' passed
Executed 4 tests, with 0 failures (0 unexpected)
evaluated-squat-signals knee_left=valid(180.000, confidence: 1.000) knee_raw=valid(180.000, confidence: 1.000) knee_right=valid(180.000, confidence: 1.000) knee_symmetry=valid(0.000, confidence: 1.000) torso_raw=valid(0.000, confidence: 1.000)
low-visibility-reason low confidence landmark left.knee visibility=0.2 presence=1.0 threshold=0.65
invalid-arithmetic invalid(divide by zero) invalid(degenerate angle)
```

Broad validation:

```text
swift build --disable-sandbox

Build complete! (0.15s)
```

```text
swift test --disable-sandbox

Test Suite 'All tests' passed
Executed 13 tests, with 0 failures (0 unexpected)
evaluated-squat-signals knee_left=valid(180.000, confidence: 1.000) knee_raw=valid(180.000, confidence: 1.000) knee_right=valid(180.000, confidence: 1.000) knee_symmetry=valid(0.000, confidence: 1.000) torso_raw=valid(0.000, confidence: 1.000)
low-visibility-reason low confidence landmark left.knee visibility=0.2 presence=1.0 threshold=0.65
invalid-arithmetic invalid(divide by zero) invalid(degenerate angle)
```

## Reachability Evidence

`SignalEvaluatorTests.testEvaluatesSquatPresetSignalsFromSyntheticStandingPose` loads the real product preset:

```swift
let program = try ProgramLoader.load(from: presetURL)
let evaluator = try SignalEvaluator(program: program)
let values = evaluator.evaluateSignals(frame: standingFrame)
```

The test prints the stable evaluated raw-signal table:

```text
evaluated-squat-signals knee_left=valid(180.000, confidence: 1.000) knee_raw=valid(180.000, confidence: 1.000) knee_right=valid(180.000, confidence: 1.000) knee_symmetry=valid(0.000, confidence: 1.000) torso_raw=valid(0.000, confidence: 1.000)
```

## Flags For Reviewer

- This slice intentionally implements only the numeric subset from brief 003. It does not evaluate comparisons, boolean operators, `in`, `between`, strings/lists, state vars, rep predicates, form rules, hold ranges, or filters.
- `primary.*` landmarks are supplied by the `PoseFrame` caller. There is no frame-by-frame side selection in the evaluator.
- The evaluator currently returns invalid values for unsupported allowlisted functions that are outside this slice, rather than widening scope.
- No network, model download, Python, MediaPipe, camera, UI, Layer 2, or Layer 3 work was added.

## Next Suggested Slice

Add comparison and predicate expression evaluation for `rep.down_when` / `rep.up_when` as a stepping stone toward the rep state machine, or implement the filter runtime (`ema`, `median`) if Reviewer wants the raw-signal table connected to produced filter outputs first.
