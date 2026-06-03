# Executor Session 011 - Basic Form Rule Evaluator

**Date:** 2026-06-03  
**Role:** Executor  
**Active brief:** `docs/briefs/011-form-rule-evaluator-basic.md`

## Slice Summary

Implemented the smallest pure Swift form-rule evaluator for the current squat preset:

- Added `FormRuleEvaluator`, initialized from `ExerciseProgram.formRules`.
- Added `FormRuleSnapshot` with rule id, active state, expectation result, cue, severity, and invalid reason.
- Reused the existing numeric expression parser/evaluator for rule `expect` predicates.
- Added narrow phase-condition parsing for current preset `when` expressions:
  - `phase == 'bottom'`
  - `phase in ['descending','bottom']`
- Active rules emit configured cue text only when the expectation is false.
- Missing or invalid produced values produce invalid snapshots without cueing or crashing.

## Files Changed

- `Sources/CamiFitEngine/FormRuleEvaluator.swift`
- `Tests/CamiFitEngineTests/FormRuleEvaluatorTests.swift`
- `docs/session-logs/011-executor-form-rule-evaluator-basic.md`

## Validation

Startup workflow audit:

```bash
scripts/audit_autonomous_workflow.sh
```

Result before implementation: clean.

Focused red check before production code:

```bash
swift test --disable-sandbox --filter FormRuleEvaluatorTests
```

Result: failed as expected because the tests referenced the new form-rule surface before implementation:

- `cannot find type 'FormRuleSnapshot' in scope`
- `cannot find type 'FormRuleEvaluator' in scope`

Focused validation after implementation:

```bash
swift test --disable-sandbox --filter FormRuleEvaluatorTests
```

Result:

- 6 tests executed.
- 0 failures.

Focused evidence:

```text
form-rules-preset ids=depth,torso,symmetry
form-rule-depth-fail id=depth active=true passed=false severity=warn cue=Go deeper
form-rule-depth-pass id=depth active=true passed=true severity=warn
form-rule-torso descending=id=torso active=true passed=true severity=warn bottom=id=torso active=true passed=true severity=warn ready=id=torso active=false passed=nil severity=warn
form-rule-invalid missing=id=depth active=true passed=nil severity=warn invalid=missing signal knee invalid=id=depth active=true passed=nil severity=warn invalid=signal knee invalid: low confidence landmark primary.knee
```

Broad validation:

```bash
swift build --disable-sandbox
swift test --disable-sandbox
```

Result:

- Build completed successfully.
- Full test suite executed 40 tests with 0 failures.

## Reachability Proof

The form-rule integration test reaches the evaluator through the real squat product path:

1. `ProductPathHarness` loads `Presets/bodyweight_squat.json`.
2. It initializes `FrameSignalProcessor`, `RepPredicateEvaluator`, `RepStateMachine`, and `FormRuleEvaluator` from the loaded program.
3. Synthetic timestamped squat frames are processed through `FrameSignalProcessor`.
4. Produced values are evaluated by `RepPredicateEvaluator`.
5. The configured phase signal and predicates are fed into `RepStateMachine.update`.
6. The resulting `RepStateSnapshot.phase` and produced values are fed into `FormRuleEvaluator.evaluate`.

Product-path evidence:

```text
form-rule-product-path phase=bottom id=depth active=true passed=true severity=warn | id=torso active=true passed=true severity=warn | id=symmetry active=true passed=true severity=info
```

That proves loaded preset form rules are evaluated from real produced values and the current rep phase, not from hard-coded booleans.

## Flags For Reviewer

- This slice intentionally supports only the current preset form-rule syntax: numeric comparisons plus phase equality/membership.
- This slice does not implement temporal `min_violation_ms`, form-rule `cooldown_ms`, weighted scoring, post-set summary, replay/debugger output, UI, audio, Python, MediaPipe, camera, network access, package dependencies, Layer 2, or Layer 3 behavior.
- Invalid/missing expected values are treated as invalid snapshots, not violations, so they do not cue.
- `FormRuleEvaluator` duplicates the numeric predicate comparison mechanics from `RepPredicateEvaluator` locally rather than refactoring shared internals during this slice.

## Next Suggested Slice

Add the smallest temporal form-rule persistence slice: honor `min_violation_ms` for active unsatisfied rules across timestamped frames and continue to defer cue cooldowns, weighted scoring, replay, UI, and golden fixtures.
