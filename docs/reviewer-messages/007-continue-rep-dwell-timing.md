# Reviewer Decision 007 - Rep Dwell Timing

**Date:** 2026-06-03

## Decision

`CONTINUE`

## Evidence Reviewed

- Active mission and validation convention in `GOAL.md`.
- Workflow rules in `executor-reviewer-pair-programming.md` and `docs/autonomous-workflow/`.
- Active brief: `docs/briefs/007-rep-state-machine-dwell-timing.md`.
- Executor log: `docs/session-logs/007-executor-rep-state-machine-dwell-timing.md`.
- Latest commit: `e631b3d feat: enforce rep dwell timing`.
- Current repo state before reviewer edits: clean worktree.

## Findings

- The slice matches brief 007's boundary: it adds timestamped `RepStateMachine.update`, expands phases to `descending`, `bottom`, and `ascending`, and enforces `down_min_ms`, `bottom_min_ms`, and `up_min_ms`.
- Product-path reachability remains intact: `RepStateMachineTests.ProductPathHarness` loads `Presets/bodyweight_squat.json`, processes timestamped synthetic frames through `FrameSignalProcessor`, evaluates predicates through `RepPredicateEvaluator`, and feeds timestamped updates into `RepStateMachine`.
- The valid timed sequence counts exactly one rep only after the configured dwell phases complete.
- The too-fast threshold-crossing sequence counts zero reps.
- Invalid predicate frames preserve an explicit invalid reason and do not count or advance active dwell timing.
- The slice stayed out of deferred scope: no `min_rom_deg`, `cooldown_ms`, set tracking, hold evaluator, form rules, cue scoring, replay debugger, UI, audio, Python, MediaPipe, camera, network, Layer 2, or Layer 3 behavior.

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
Executed 28 tests, with 0 failures (0 unexpected)
rep-state-timed-one-rep ... 16:ready:reps=1:counted=true ...
rep-state-too-fast ... 30:ready:reps=0:counted=false
rep-state-invalid-dwell ... invalid=phase=descending reps=0 counted=false invalid=down predicate invalid: signal knee invalid: filter knee source knee_raw invalid: low confidence landmark primary.knee visibility=0.2 presence=1.0 threshold=0.65
```

## Routing

Advance to ROM enforcement. The state machine now has defensible timestamped dwell transitions, but `RepConfig.min_rom_deg` is still not enforced. Add ROM tracking next so a rep must satisfy both time and movement range before cooldown or set-level behavior is introduced.

## Next Action

Execute `docs/briefs/008-rep-rom-enforcement.md`.

## Manager / Human Escalation

None.
