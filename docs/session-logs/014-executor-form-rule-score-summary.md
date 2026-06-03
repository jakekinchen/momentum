# Executor Session 014 - Form Rule Score Summary

**Date:** 2026-06-03  
**Role:** Executor  
**Active brief:** `docs/briefs/014-form-rule-score-summary.md`

## Slice Summary

Added a deterministic form-rule score summary layer:

- `FormRuleScoreSummarizer` consumes current `[FormRuleSnapshot]` and loaded program `form_rules`.
- `FormRuleScoreSummary` reports normalized `score`, earned/possible weights, active/scored counts, invalid-active count, and the selected current cue.
- Passing active valid rules earn full configured `score_weight`.
- Failed active valid rules contribute to the denominator but earn no weight.
- Inactive rules are excluded from the denominator.
- Invalid active rules are excluded from the denominator and counted in `invalidActiveRuleCount`.
- Cue selection is deterministic: higher current snapshot severity, then higher program `score_weight`, then original program rule order.

This slice did not change `FormRuleEvaluator` cue timing, `min_violation_ms`, or `cooldown_ms` semantics.

## Files Changed

- `Sources/CamiFitEngine/FormRuleEvaluator.swift`
- `Tests/CamiFitEngineTests/FormRuleEvaluatorTests.swift`
- `docs/session-logs/014-executor-form-rule-score-summary.md`

## Validation

Startup workflow audit:

```bash
scripts/audit_autonomous_workflow.sh
```

Result before implementation: clean.

Focused checks during implementation:

```bash
swift test --disable-sandbox --filter FormRuleEvaluatorTests
```

Results:

- First failed because new tests called the static `snapshot` helper without `Self.`.
- Second failed because an optional score was passed to an accuracy-based `XCTAssertEqual`.
- Third failed the severity-priority cue case, exposing that cue priority used program metadata severity instead of the current snapshot severity.

Final focused validation:

```bash
swift test --disable-sandbox --filter FormRuleEvaluatorTests
```

Result:

- 14 tests executed.
- 0 failures.

Focused evidence:

```text
form-rule-score-full score=1.000 earned_weight=22.000 possible_weight=22.000 active_rules=3 scored_rules=3 invalid_active_rules=0
form-rule-score-weighted-fail score=0.636 earned_weight=14.000 possible_weight=22.000 active_rules=3 scored_rules=3 invalid_active_rules=0 cue_rule=torso cue=Chest up
form-rule-score-invalid-policy score=1.000 earned_weight=10.000 possible_weight=10.000 active_rules=2 scored_rules=1 invalid_active_rules=1
form-rule-score-cue-priority severity=score=0.000 earned_weight=0.000 possible_weight=14.000 active_rules=2 scored_rules=2 invalid_active_rules=0 cue_rule=symmetry cue=Even both sides weight=score=0.000 earned_weight=0.000 possible_weight=18.000 active_rules=2 scored_rules=2 invalid_active_rules=0 cue_rule=depth cue=Go deeper order=score=0.000 earned_weight=0.000 possible_weight=10.000 active_rules=2 scored_rules=2 invalid_active_rules=0 cue_rule=first cue=First cue
```

Broad validation:

```bash
swift build --disable-sandbox
swift test --disable-sandbox
```

Result:

- Build completed successfully.
- Full test suite executed 48 tests with 0 failures.

## Reachability Proof

The product-path integration test now sends loaded squat form snapshots through the score-summary path:

1. `ProductPathHarness` loads `Presets/bodyweight_squat.json`.
2. It initializes `FrameSignalProcessor`, `RepPredicateEvaluator`, `RepStateMachine`, `FormRuleEvaluator`, and `FormRuleScoreSummarizer`.
3. Synthetic timestamped squat frames are processed through `FrameSignalProcessor`.
4. Produced values are evaluated by `RepPredicateEvaluator`.
5. The configured phase signal and predicates are fed into `RepStateMachine.update`.
6. `RepStateSnapshot.phase`, produced values, source frame, and `frame.timestampMS` feed `FormRuleEvaluator.update`.
7. The resulting snapshots feed `FormRuleScoreSummarizer.summarize`.

Product-path evidence:

```text
form-rule-product-path phase=bottom id=depth active=true passed=true severity=warn | id=torso active=true passed=true severity=warn | id=symmetry active=true passed=true severity=info summary=score=1.000 earned_weight=22.000 possible_weight=22.000 active_rules=3 scored_rules=3 invalid_active_rules=0
```

## Flags For Reviewer

- Invalid active rules are excluded from score denominator and counted separately. This is documented here as the slice policy.
- Cue priority uses current snapshot severity, not just original program metadata severity, then program weight and original rule order.
- Unknown snapshot rule ids are tolerated with weight `0` and last-order priority; this keeps summary robust if a caller supplies extra snapshots but should not happen on the normal product path.
- This slice does not add per-rep rollups, set-level summaries, replay/debugger output, UI, audio, Python, MediaPipe, camera, network access, package dependencies, Layer 2, or Layer 3 behavior.

## Next Suggested Slice

Add the smallest replay/debug trace slice for form/score output: a deterministic trace record that captures frame timestamp, rep phase, form snapshots, and score summary for existing synthetic product-path frames, without adding UI, camera, MediaPipe, or recorded landmark fixtures yet.
