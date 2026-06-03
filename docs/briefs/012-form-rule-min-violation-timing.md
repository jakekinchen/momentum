# Slice Brief 012 - Form Rule Min-Violation Timing

**Date:** 2026-06-03

## Objective

Extend the form-rule evaluator to honor each rule's `min_violation_ms`: an active unsatisfied rule should emit a cue only after the violation has persisted for the configured duration across timestamped frames.

Keep this pure Swift and offline: no MediaPipe, no Python worker, no camera, no network, no package dependencies.

## Product / Project Value

Basic form-rule evaluation now works from the loaded squat preset, but immediate cueing would flicker on single noisy frames. `min_violation_ms` is the next deterministic form-rule guardrail before cue cooldowns, scoring, replay, or UI.

## Scope

- Add timestamp input to the form-rule evaluation path, either directly or through a small update context.
- Track active unsatisfied duration per rule id.
- Emit the configured cue only when an active unsatisfied rule has persisted for at least `min_violation_ms`.
- Preserve immediate cue behavior for rules whose `min_violation_ms == 0`.
- Reset or clear a rule's violation timer when the rule becomes inactive, passes, or evaluates invalid.
- Preserve current snapshot fields and add only minimal evidence fields if useful, such as `violationDurationMS`.
- Keep invalid/missing produced values as skipped/invalid snapshots without cueing.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass using the default in-repo `.build`.
- Focused tests prove:
  - a `min_violation_ms = 0` rule, such as `depth`, can cue immediately when active and unsatisfied;
  - a rule with `min_violation_ms = 250`, such as `torso`, does not cue on the first unsatisfied frame;
  - the same rule cues only after unsatisfied active frames persist through the configured duration;
  - passing, inactive, or invalid frames reset the pending violation timer and do not cue.
- At least one product-path integration test processes timestamped synthetic frames through `FrameSignalProcessor`, `RepPredicateEvaluator`, `RepStateMachine`, and `FormRuleEvaluator` to prove temporal form snapshots are reachable from the loaded preset.
- Existing `ProgramLoaderTests`, `SignalEvaluatorTests`, `FilterPipelineTests`, `RepPredicateEvaluatorTests`, `RepStateMachineTests`, `SetProgressTrackerTests`, and current `FormRuleEvaluatorTests` remain green or are intentionally updated to the timing contract.

## Expected Files

- `Sources/CamiFitEngine/FormRuleEvaluator.swift`
- `Tests/CamiFitEngineTests/FormRuleEvaluatorTests.swift`
- `docs/session-logs/012-executor-form-rule-min-violation-timing.md`

Names may change if the implementation finds a cleaner local structure, but keep the form-rule timing boundary explicit.

## Validation Commands

```bash
cd /Users/kelly/Developer/camifit
swift build --disable-sandbox
swift test --disable-sandbox
```

## Evidence To Record

- `swift build --disable-sandbox` result.
- `swift test --disable-sandbox` test count and pass/fail.
- Printed focused rule timeline showing violation duration, no early cue, eventual cue, and reset behavior.
- Printed product-path proof showing timestamped form-rule snapshots from synthetic frames.

## Reachability / Demo Proof

A test must load the real `Presets/bodyweight_squat.json`, process timestamped synthetic frames through `FrameSignalProcessor`, evaluate predicates through `RepPredicateEvaluator`, feed `RepStateMachine`, and evaluate form rules from the resulting phase plus produced values and timestamps. Do not prove timing only with hard-coded booleans.

## Out Of Scope

- Form-rule `cooldown_ms` cue throttling.
- Weighted scoring or post-set summary.
- Replay debugger, UI, audio, Python MediaPipe worker, camera, transport, model download, Layer 2, or Layer 3.
- Golden landmark fixtures and no-person acceptance gates.

## Stop Conditions

- ESCALATE before adding any remote dependency, network access, model download, Python worker, camera code, or Layer 2/3 behavior.
- STOP if `swift test --disable-sandbox` cannot run with the default in-repo `.build`; record the exact failure.
- Do not claim coaching accuracy or milestone completion from this slice. Cue cooldowns, scoring, replay, UI, pose fixtures, and no-person/low-visibility acceptance gates are still required later.
