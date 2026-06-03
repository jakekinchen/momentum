# Slice Brief 013 - Form Rule Cue Cooldown

**Date:** 2026-06-03

## Objective

Extend the form-rule evaluator to honor each rule's `cooldown_ms`: after a cue is emitted for a rule, suppress repeat cue emission for that rule until the configured cooldown has elapsed.

Keep this pure Swift and offline: no MediaPipe, no Python worker, no camera, no network, no package dependencies.

## Product / Project Value

Form rules now evaluate from the loaded preset and respect `min_violation_ms`. Cue cooldown is the next deterministic guardrail: it prevents repeated noisy cue spam while preserving the underlying violation state needed for later scoring and replay.

## Scope

- Track last cue emission time per rule id.
- Emit a cue only when:
  - the rule is active;
  - expectation is unsatisfied;
  - `min_violation_ms` has been satisfied;
  - and `cooldown_ms` has elapsed since the previous cue for that rule.
- Preserve violation tracking while cue output is suppressed by cooldown.
- Preserve immediate cue behavior for `min_violation_ms == 0` rules when cooldown allows.
- Reset or retain cooldown state conservatively according to the simplest deterministic local rule; document the chosen behavior in the session log.
- Keep invalid/missing produced values as skipped/invalid snapshots without cueing.
- Add minimal evidence fields only if useful, such as `cueCooldownRemainingMS`.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass using the default in-repo `.build`.
- Focused tests prove:
  - the first eligible cue emits after `min_violation_ms` is satisfied;
  - repeated active unsatisfied frames inside `cooldown_ms` do not emit a second cue;
  - a later active unsatisfied frame after cooldown elapses emits a second cue;
  - invalid, inactive, or passing frames do not emit cues and do not break later eligible cue behavior.
- At least one product-path integration test processes timestamped synthetic frames through `FrameSignalProcessor`, `RepPredicateEvaluator`, `RepStateMachine`, and `FormRuleEvaluator` to prove cooldown-aware form snapshots are reachable from the loaded preset.
- Existing `ProgramLoaderTests`, `SignalEvaluatorTests`, `FilterPipelineTests`, `RepPredicateEvaluatorTests`, `RepStateMachineTests`, `SetProgressTrackerTests`, and current `FormRuleEvaluatorTests` remain green or are intentionally updated to the cooldown contract.

## Expected Files

- `Sources/CamiFitEngine/FormRuleEvaluator.swift`
- `Tests/CamiFitEngineTests/FormRuleEvaluatorTests.swift`
- `docs/session-logs/013-executor-form-rule-cue-cooldown.md`

Names may change if the implementation finds a cleaner local structure, but keep the form-rule cooldown boundary explicit.

## Validation Commands

```bash
cd /Users/kelly/Developer/camifit
swift build --disable-sandbox
swift test --disable-sandbox
```

## Evidence To Record

- `swift build --disable-sandbox` result.
- `swift test --disable-sandbox` test count and pass/fail.
- Printed focused rule timeline showing first cue, suppressed in-cooldown cue, and later cue after cooldown.
- Printed product-path proof showing cooldown-aware timestamped form-rule snapshots from synthetic frames.

## Reachability / Demo Proof

A test must load the real `Presets/bodyweight_squat.json`, process timestamped synthetic frames through `FrameSignalProcessor`, evaluate predicates through `RepPredicateEvaluator`, feed `RepStateMachine`, and evaluate form rules from the resulting phase plus produced values and timestamps. Do not prove cue cooldown only with hard-coded booleans.

## Out Of Scope

- Weighted scoring or post-set summary.
- Replay debugger, UI, audio, Python MediaPipe worker, camera, transport, model download, Layer 2, or Layer 3.
- Golden landmark fixtures and no-person acceptance gates.

## Stop Conditions

- ESCALATE before adding any remote dependency, network access, model download, Python worker, camera code, or Layer 2/3 behavior.
- STOP if `swift test --disable-sandbox` cannot run with the default in-repo `.build`; record the exact failure.
- Do not claim coaching accuracy or milestone completion from this slice. Scoring, replay, UI, pose fixtures, and no-person/low-visibility acceptance gates are still required later.
