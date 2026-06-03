# Reviewer Decision 009 - Rep Cooldown Enforcement

**Date:** 2026-06-03

## Decision

`CONTINUE`

## Evidence Reviewed

- Active mission and validation convention in `GOAL.md`.
- Workflow rules in `executor-reviewer-pair-programming.md` and `docs/autonomous-workflow/`.
- Active brief: `docs/briefs/009-rep-cooldown-enforcement.md`.
- Executor log: `docs/session-logs/009-executor-rep-cooldown-enforcement.md`.
- Latest commit: `d29e626 feat: enforce rep cooldown`.
- Current repo state before reviewer edits: clean worktree.

## Findings

- The slice matches brief 009's boundary: `RepStateMachine` now tracks an explicit cooldown-until timestamp after counted reps, exposes `cooldownRemainingMS` in `RepStateSnapshot`, and blocks new attempts while cooldown remains active.
- Product-path reachability remains intact: `RepStateMachineTests.ProductPathHarness` loads `Presets/bodyweight_squat.json`, processes timestamped synthetic frames through `FrameSignalProcessor`, evaluates predicates through `RepPredicateEvaluator`, reads the configured phase signal from produced values, and feeds it into `RepStateMachine`.
- The valid timed + ROM preset path still counts exactly one rep and shows the real preset's `250` ms cooldown.
- The cooldown test isolates the gate with a derived `RepConfig.cooldownMS = 5000`, proves the second threshold-crossing sequence inside cooldown does not count, and proves a later after-cooldown sequence counts one additional rep.
- Invalid phase-signal frames during cooldown do not count and do not prevent a later valid attempt.
- The slice stayed out of deferred scope: no set tracking, rest detection, hold evaluator, form rules, cue scoring, replay debugger, UI, audio, Python, MediaPipe, camera, network, Layer 2, or Layer 3 behavior.

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
Executed 30 tests, with 0 failures (0 unexpected)
rep-state-timed-one-rep ... 16:ready:reps=1:counted=true:rom=82.1:cooldown=250 ...
rep-state-cooldown ... 16:ready:reps=1:counted=true:rom=82.1:cooldown=5000 ... 55:ready:reps=2:counted=true:rom=82.1:cooldown=5000 ...
invalid=phase=ready reps=1 counted=false cooldown=2400 invalid=phase signal knee invalid: filter knee source knee_raw invalid: low confidence landmark primary.knee visibility=0.2 presence=1.0 threshold=0.65
```

## Routing

Advance to minimal set progress tracking. The rep FSM now covers the configured rep guardrails: predicates, dwell timing, ROM, and cooldown. The next smallest M1 step is a pure Swift layer that consumes counted-rep events and `set.target_reps` without adding form rules, replay, UI, or pose-worker work.

## Next Action

Execute `docs/briefs/010-set-progress-tracker.md`.

## Manager / Human Escalation

None.
