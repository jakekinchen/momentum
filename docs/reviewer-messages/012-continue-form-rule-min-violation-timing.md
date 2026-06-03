# Reviewer Decision 012 - Form Rule Min-Violation Timing

**Date:** 2026-06-03

## Decision

`CONTINUE`

## Evidence Reviewed

- Active mission and validation convention in `GOAL.md`.
- Workflow rules in `executor-reviewer-pair-programming.md` and `docs/autonomous-workflow/`.
- Active brief: `docs/briefs/012-form-rule-min-violation-timing.md`.
- Executor log: `docs/session-logs/012-executor-form-rule-min-violation-timing.md`.
- Latest commit: `ec035b2 feat: honor form rule violation timing`.
- Current repo state before reviewer edits: clean worktree.

## Findings

- The slice matches brief 012's boundary: `FormRuleEvaluator.update` now accepts timestamps, tracks active unsatisfied duration per rule id, emits cues only after `min_violation_ms`, preserves immediate cueing for zero-duration rules, and clears pending violation state on passing, inactive, or invalid frames.
- Product-path reachability is preserved: `FormRuleEvaluatorTests.ProductPathHarness` loads `Presets/bodyweight_squat.json`, processes timestamped synthetic frames through `FrameSignalProcessor`, evaluates rep predicates, feeds `RepStateMachine`, and calls the timestamped form-rule update path.
- Focused tests cover immediate `depth` cueing, delayed `torso` cueing at 250 ms, and timer reset after passing, inactive, or invalid frames.
- Invalid/missing produced values remain non-cueing invalid snapshots.
- The slice stayed out of deferred scope: no form-rule `cooldown_ms`, weighted scoring, post-set summary, replay debugger, UI, audio, Python, MediaPipe, camera, network, Layer 2, or Layer 3 behavior.

## Validation

Reviewer reproduction:

```text
scripts/audit_autonomous_workflow.sh
workflow audit clean
```

```text
swift build --disable-sandbox
Build complete! (0.15s)
```

```text
swift test --disable-sandbox
Test Suite 'All tests' passed
Executed 42 tests, with 0 failures (0 unexpected)
form-rule-depth-fail id=depth active=true passed=false severity=warn violation_ms=0 cue=Go deeper
form-rule-torso-timing first=id=torso active=true passed=false severity=warn violation_ms=0 early=id=torso active=true passed=false severity=warn violation_ms=100 ready=id=torso active=true passed=false severity=warn violation_ms=250 cue=Chest up
form-rule-product-path phase=bottom id=depth active=true passed=true severity=warn | id=torso active=true passed=true severity=warn | id=symmetry active=true passed=true severity=info
```

## Routing

Advance to form-rule cue cooldowns. Form rules now have basic evaluation and `min_violation_ms` persistence; the next narrow contract field is `cooldown_ms`, suppressing repeated cue emission for the same rule while the violation remains active.

## Next Action

Execute `docs/briefs/013-form-rule-cue-cooldown.md`.

## Manager / Human Escalation

None.
