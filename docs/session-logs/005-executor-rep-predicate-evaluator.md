# Executor Session 005 - Rep Predicate Evaluator

Date: 2026-06-03
Role: Executor
Brief: `docs/briefs/005-rep-predicate-evaluator.md`
Slice: boolean comparison predicates for `rep.down_when` and `rep.up_when`.

## Slice

Implemented the predicate layer that later rep state-machine work can call:

- Added comparison tokens for `<`, `<=`, `>`, `>=`, `==`, and `!=`.
- Added a separate predicate parse entry point so existing numeric expression parsing remains unchanged.
- Added `PredicateResult` with explicit `true`, `false`, and `invalid(reason:)` descriptions.
- Added `RepPredicateEvaluator`, initialized either from an `ExerciseProgram` or direct predicate strings.
- Evaluated predicate operands through the existing numeric `ExpressionEvaluator` against produced `SignalValue`s.
- Missing or invalid source signals return invalid predicate results instead of false.
- Unsupported boolean composition such as `and` fails closed at parse time.

## Files Changed

- `Sources/CamiFitEngine/Expression/AST.swift`
- `Sources/CamiFitEngine/Expression/Lexer.swift`
- `Sources/CamiFitEngine/Expression/Parser.swift`
- `Sources/CamiFitEngine/RepPredicateEvaluator.swift`
- `Tests/CamiFitEngineTests/RepPredicateEvaluatorTests.swift`
- `docs/session-logs/005-executor-rep-predicate-evaluator.md`

## Validation

Startup audit:

```text
git status --short --branch --untracked-files=all
## main

scripts/audit_autonomous_workflow.sh
workflow audit clean
```

Test-first red run:

```text
swift test --disable-sandbox --filter RepPredicateEvaluatorTests

RepPredicateEvaluatorTests.swift:125:18: error: cannot find type 'PredicateResult' in scope
RepPredicateEvaluatorTests.swift:6:29: error: cannot find 'RepPredicateEvaluator' in scope
```

Focused validation:

```text
swift test --disable-sandbox --filter RepPredicateEvaluatorTests

Test Suite 'RepPredicateEvaluatorTests' passed
Executed 4 tests, with 0 failures (0 unexpected)
invalid-predicate missing=invalid(missing signal knee) invalid=invalid(signal knee invalid: low confidence landmark primary.knee)
rep-predicate-product-path standing down=false up=true knee=valid(180.000, confidence: 1.000) deep down=true up=false knee=valid(90.000, confidence: 1.000)
```

Broad validation:

```text
swift build --disable-sandbox

Build complete! (0.15s)
```

```text
swift test --disable-sandbox

Test Suite 'All tests' passed
Executed 22 tests, with 0 failures (0 unexpected)
invalid-predicate missing=invalid(missing signal knee) invalid=invalid(signal knee invalid: low confidence landmark primary.knee)
rep-predicate-product-path standing down=false up=true knee=valid(180.000, confidence: 1.000) deep down=true up=false knee=valid(90.000, confidence: 1.000)
```

## Reachability Evidence

`RepPredicateEvaluatorTests.testSquatPresetPredicatesEvaluateFromFrameSignalProcessorOutput` loads the real product preset and evaluates the real predicate strings from the loaded program:

```swift
let program = try ProgramLoader.load(from: presetURL)
var processor = try FrameSignalProcessor(program: program)
let evaluator = try RepPredicateEvaluator(program: program)
let standingProduced = processor.process(frame: standingFrame)
let standingDown = evaluator.evaluateDown(producedValues: standingProduced, frame: standingFrame)
let standingUp = evaluator.evaluateUp(producedValues: standingProduced, frame: standingFrame)
```

The printed evidence proves the configured squat thresholds are reachable from the product path:

```text
rep-predicate-product-path standing down=false up=true knee=valid(180.000, confidence: 1.000) deep down=true up=false knee=valid(90.000, confidence: 1.000)
```

Invalid and missing `knee` paths are also explicit:

```text
invalid-predicate missing=invalid(missing signal knee) invalid=invalid(signal knee invalid: low confidence landmark primary.knee)
```

## Flags For Reviewer

- This slice intentionally does not implement the rep phase state machine, dwell timing, ROM, cooldown, set tracking, hold logic, form rules, validity timing, UI, Python, MediaPipe, network, Layer 2, or Layer 3.
- Predicate expressions support exactly one numeric comparison. Boolean composition remains out of scope and fails closed during parsing.
- Equality and inequality use a small numeric tolerance (`1e-9`) to avoid brittle floating-point equality checks.
- Predicate operands reuse `ExpressionEvaluator`, so invalid/missing produced values preserve existing signal error wording.

## Next Suggested Slice

Implement the smallest rep phase state machine over the produced-value table and predicate evaluator: standing -> down -> up transition with no dwell/ROM/cooldown yet beyond preserving the configured fields for later enforcement.
