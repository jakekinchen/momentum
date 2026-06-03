# Reviewer Decision 006 - Basic Rep State Machine

**Date:** 2026-06-03

## Decision

`CONTINUE`

## Evidence Reviewed

- Active mission and validation convention in `GOAL.md`.
- Workflow rules in `executor-reviewer-pair-programming.md` and `docs/autonomous-workflow/`.
- Active brief: `docs/briefs/006-rep-state-machine-basic.md`.
- Executor log: `docs/session-logs/006-executor-rep-state-machine-basic.md`.
- Latest commit: `77e7505 feat: add basic rep state machine`.
- Current repo state before reviewer edits: clean worktree.

## Findings

- The slice matches brief 006's boundary: it adds `RepStateMachine`, `RepPhase`, `RepStateSnapshot`, product-path tests, and invalid-frame handling without adding dwell timing, ROM, cooldown, set tracking, hold/form logic, validity freeze/reset timing, Python, MediaPipe, UI, network, or Layer 2/3 behavior.
- Product-path reachability is covered: `RepStateMachineTests.ProductPathHarness` loads `Presets/bodyweight_squat.json`, processes synthetic frames through `FrameSignalProcessor`, evaluates predicates through `RepPredicateEvaluator`, and feeds them into `RepStateMachine`.
- The one-rep sequence counts exactly one rep and records a stable timeline.
- The no-false-rep cases are covered for repeated standing, shallow movement, and deep-start-before-ready.
- Invalid `knee` frames do not count and preserve an invalid reason naming `knee`.

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
Executed 26 tests, with 0 failures (0 unexpected)
rep-state-one-rep 0:ready:reps=0:counted=false ... 10:ready:reps=1:counted=true 11:ready:reps=1:counted=false
rep-state-invalid phase=ready reps=0 counted=false invalid=down predicate invalid: signal knee invalid: filter knee source knee_raw invalid: low confidence landmark primary.knee visibility=0.2 presence=1.0 threshold=0.65
```

## Routing

Advance to dwell timing. The current state machine proves basic phase/count behavior, but the contract's `down_min_ms`, `bottom_min_ms`, and `up_min_ms` are still not enforced. Add timing before ROM/cooldown/set tracking so later rep events have defensible timestamps.

## Next Action

Execute `docs/briefs/007-rep-state-machine-dwell-timing.md`.

## Manager / Human Escalation

None.
