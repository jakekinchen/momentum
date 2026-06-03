# Executor Session 012 - Form Rule Min-Violation Timing

**Date:** 2026-06-03  
**Role:** Executor  
**Active brief:** `docs/briefs/012-form-rule-min-violation-timing.md`

## Slice Summary

Extended the pure Swift form-rule evaluator to honor `FormRule.minViolationMS` on the timestamped update path:

- Added `violationDurationMS` to `FormRuleSnapshot`.
- Added `FormRuleEvaluator.update(timestampMS:producedValues:phase:frame:)`.
- Track active unsatisfied violation start time per rule id.
- Cue only when the active unsatisfied duration reaches the configured `min_violation_ms`.
- Preserve immediate cueing for `min_violation_ms == 0`, such as the preset `depth` rule.
- Reset pending violation state when a rule passes, becomes inactive, or evaluates invalid.
- Kept the existing stateless `evaluate(...)` path for basic one-frame evaluation.

## Files Changed

- `Sources/CamiFitEngine/FormRuleEvaluator.swift`
- `Tests/CamiFitEngineTests/FormRuleEvaluatorTests.swift`
- `docs/session-logs/012-executor-form-rule-min-violation-timing.md`

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

Result: failed as expected because the tests referenced the new timing API and evidence field before implementation:

- `value of type 'FormRuleEvaluator' has no member 'update'`
- follow-on type inference errors from the missing timestamped API

Focused validation after implementation:

```bash
swift test --disable-sandbox --filter FormRuleEvaluatorTests
```

Result:

- 8 tests executed.
- 0 failures.

Focused evidence:

```text
form-rule-depth-fail id=depth active=true passed=false severity=warn violation_ms=0 cue=Go deeper
form-rule-torso-timing first=id=torso active=true passed=false severity=warn violation_ms=0 early=id=torso active=true passed=false severity=warn violation_ms=100 ready=id=torso active=true passed=false severity=warn violation_ms=250 cue=Chest up
form-rule-reset passing=id=torso active=true passed=false severity=warn violation_ms=0 inactive=id=torso active=true passed=false severity=warn violation_ms=0 invalid=id=torso active=true passed=false severity=warn violation_ms=0
```

Broad validation:

```bash
swift build --disable-sandbox
swift test --disable-sandbox
```

Result:

- Build completed successfully.
- Full test suite executed 42 tests with 0 failures.

## Reachability Proof

The form-rule product-path integration test now calls the timestamped update path:

1. `ProductPathHarness` loads `Presets/bodyweight_squat.json`.
2. It initializes `FrameSignalProcessor`, `RepPredicateEvaluator`, `RepStateMachine`, and mutable `FormRuleEvaluator`.
3. Synthetic timestamped squat frames are processed through `FrameSignalProcessor`.
4. Produced values are evaluated by `RepPredicateEvaluator`.
5. The configured phase signal and predicates are fed into `RepStateMachine.update`.
6. The resulting `RepStateSnapshot.phase`, produced values, source frame, and `frame.timestampMS` are fed into `FormRuleEvaluator.update`.

Product-path evidence:

```text
form-rule-product-path phase=bottom id=depth active=true passed=true severity=warn | id=torso active=true passed=true severity=warn | id=symmetry active=true passed=true severity=info
```

That proves timestamped form-rule snapshots are reachable from the loaded preset and real produced values. Focused timing tests separately prove delayed cue behavior for the preset `torso` rule and immediate cue behavior for the preset `depth` rule.

## Flags For Reviewer

- This slice intentionally implements only `min_violation_ms`; it does not implement form-rule `cooldown_ms`.
- The existing stateless `evaluate(...)` remains immediate and does not track timing. The product path test uses `update(...)`.
- Timing state is per `FormRuleEvaluator` instance and per rule id.
- Passing, inactive, or invalid snapshots clear pending violation state and do not cue.
- This slice does not add weighted scoring, post-set summary, replay/debugger output, UI, audio, Python, MediaPipe, camera, network access, package dependencies, Layer 2, or Layer 3 behavior.

## Next Suggested Slice

Add the smallest form-rule cue cooldown slice: after a cue emits, suppress repeat cue emission for the rule's configured `cooldown_ms` while preserving violation state and keeping scoring, replay, UI, and golden fixtures deferred.
