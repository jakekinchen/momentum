# Executor Session 013 - Form Rule Cue Cooldown

**Date:** 2026-06-03  
**Role:** Executor  
**Active brief:** `docs/briefs/013-form-rule-cue-cooldown.md`

## Slice Summary

Extended the timestamped form-rule evaluator to honor `FormRule.cooldownMS`:

- Added `cueCooldownRemainingMS` to `FormRuleSnapshot`.
- Tracked last cue emission time per rule id.
- Suppressed repeated cues while `cooldown_ms` remains active.
- Preserved active unsatisfied violation tracking while cue output is suppressed.
- Preserved immediate cue behavior for `min_violation_ms == 0` when cooldown allows.
- Kept invalid/missing produced values as non-cueing invalid snapshots.

Chosen cooldown rule: cue cooldown state is retained across passing, inactive, and invalid frames until elapsed. Violation duration still resets on passing, inactive, or invalid frames. This is the conservative local behavior: once the user hears a cue for a rule, that same rule will not cue again until its configured cooldown has passed, even if the violation briefly clears.

## Files Changed

- `Sources/CamiFitEngine/FormRuleEvaluator.swift`
- `Tests/CamiFitEngineTests/FormRuleEvaluatorTests.swift`
- `docs/session-logs/013-executor-form-rule-cue-cooldown.md`

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

Result: failed as expected because the tests referenced the new cooldown evidence field before implementation:

- `value of type 'FormRuleSnapshot' has no member 'cueCooldownRemainingMS'`

Focused validation after implementation:

```bash
swift test --disable-sandbox --filter FormRuleEvaluatorTests
```

Result:

- 10 tests executed.
- 0 failures.

Focused evidence:

```text
form-rule-cooldown first=id=torso active=true passed=false severity=warn violation_ms=250 cue_cooldown_ms=1500 cue=Chest up suppressed=id=torso active=true passed=false severity=warn violation_ms=500 cue_cooldown_ms=1250 second=id=torso active=true passed=false severity=warn violation_ms=1750 cue_cooldown_ms=1500 cue=Chest up
form-rule-cooldown-reset passing=id=torso active=true passed=false severity=warn violation_ms=250 cue_cooldown_ms=1500 cue=Chest up inactive=id=torso active=true passed=false severity=warn violation_ms=250 cue_cooldown_ms=1500 cue=Chest up invalid=id=torso active=true passed=false severity=warn violation_ms=250 cue_cooldown_ms=1500 cue=Chest up
form-rule-depth-fail id=depth active=true passed=false severity=warn violation_ms=0 cue_cooldown_ms=1500 cue=Go deeper
```

Broad validation:

```bash
swift build --disable-sandbox
swift test --disable-sandbox
```

Result:

- Build completed successfully.
- Full test suite executed 44 tests with 0 failures.

## Reachability Proof

The form-rule product-path integration test continues to call the timestamped cooldown-aware update path:

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

Focused tests prove the cooldown-specific cue behavior using the loaded preset's `torso` rule (`min_violation_ms = 250`, `cooldown_ms = 1500`) and `depth` rule (`min_violation_ms = 0`, `cooldown_ms = 1500`).

## Flags For Reviewer

- This slice implements only form-rule cue cooldowns.
- Cooldown state is retained across passing, inactive, and invalid frames until elapsed; violation timing is still reset by those frames.
- This slice does not add weighted scoring, post-set summary, replay/debugger output, UI, audio, Python, MediaPipe, camera, network access, package dependencies, Layer 2, or Layer 3 behavior.
- The stateless `evaluate(...)` path remains immediate and non-cooldown-aware; product path uses timestamped `update(...)`.

## Next Suggested Slice

Add the smallest form-rule scoring summary slice: aggregate active rule pass/fail/invalid snapshots into a deterministic per-frame or post-set score/cue summary while keeping replay, UI, audio, pose fixtures, and no-person gates deferred.
