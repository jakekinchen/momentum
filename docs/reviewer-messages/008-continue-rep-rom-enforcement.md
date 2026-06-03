# Reviewer Decision 008 - Rep ROM Enforcement

**Date:** 2026-06-03

## Decision

`CONTINUE`

## Evidence Reviewed

- Active mission and validation convention in `GOAL.md`.
- Workflow rules in `executor-reviewer-pair-programming.md` and `docs/autonomous-workflow/`.
- Active brief: `docs/briefs/008-rep-rom-enforcement.md`.
- Executor log: `docs/session-logs/008-executor-rep-rom-enforcement.md`.
- Latest commit: `1b6b5b0 feat: enforce rep rom`.
- Current repo state before reviewer edits: clean worktree.

## Findings

- The slice matches brief 008's boundary: `RepStateMachine.update` now accepts the configured phase-signal value, validates missing/invalid/non-finite phase-signal inputs, tracks active-attempt ROM, and only increments the rep count when dwell completion also satisfies `RepConfig.minROMDegrees`.
- Product-path reachability remains intact: `RepStateMachineTests.ProductPathHarness` loads `Presets/bodyweight_squat.json`, processes timestamped synthetic frames through `FrameSignalProcessor`, evaluates predicates through `RepPredicateEvaluator`, reads the configured phase signal from produced values, and feeds it into `RepStateMachine`.
- The valid timed sequence counts exactly one rep with observed ROM above the preset's `50` degree threshold.
- The below-ROM proof uses the loaded preset product path with a state-machine `RepConfig` variant raising only `minROMDegrees` to `100`; that is acceptable for this slice because the real squat preset's down/up thresholds already imply more than the preset's `50` degree ROM, and the test isolates the ROM gate without changing signal production or predicate reachability.
- Invalid phase-signal frames do not count and preserve an explicit invalid reason.
- The slice stayed out of deferred scope: no `cooldown_ms`, set tracking, rest detection, hold evaluator, form rules, cue scoring, replay debugger, UI, audio, Python, MediaPipe, camera, network, Layer 2, or Layer 3 behavior.

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
Executed 29 tests, with 0 failures (0 unexpected)
rep-state-timed-one-rep ... 16:ready:reps=1:counted=true:rom=82.1 ...
rep-state-below-rom ... 16:ready:reps=0:counted=false:rom=82.1 ...
rep-state-invalid phase=ready reps=0 counted=false invalid=phase signal knee invalid: filter knee source knee_raw invalid: low confidence landmark primary.knee visibility=0.2 presence=1.0 threshold=0.65
```

## Routing

Advance to rep cooldown enforcement. The state machine now checks predicate hysteresis, dwell timing, and ROM before counting. `RepConfig.cooldownMS` is the remaining rep-FSM contract field before moving outward to set tracking or form evaluation.

## Next Action

Execute `docs/briefs/009-rep-cooldown-enforcement.md`.

## Manager / Human Escalation

None.
