# Slice Brief 014 - Form Rule Score Summary

**Date:** 2026-06-03

## Objective

Add a deterministic form-rule scoring summary that uses each rule's `score_weight` to aggregate current `FormRuleSnapshot` results into a stable score and selected cue for the current frame.

Keep this pure Swift and offline: no MediaPipe, no Python worker, no camera, no network, no package dependencies.

## Product / Project Value

The loaded Exercise-Program already carries `score_weight`, and the engine now evaluates rules with `min_violation_ms` and `cooldown_ms`. A narrow score-summary layer makes form feedback consumable by later per-rep, set-summary, replay, and UI work without jumping ahead to those surfaces.

## Scope

- Add a small scoring type or evaluator that consumes `[FormRuleSnapshot]` plus the corresponding loaded form-rule weights.
- Compute a deterministic normalized score for active, valid form rules.
- Penalize failed active rules according to `score_weight`.
- Treat passing active rules as full credit for their weights.
- Treat inactive rules as excluded from the denominator.
- Treat invalid active rules with a conservative documented policy, such as excluded from the denominator or counted separately without penalizing; choose one and document it in the session log.
- Select one current cue from snapshots that have `cue != nil`, using deterministic priority:
  - prefer higher severity;
  - then higher `score_weight`;
  - then original program rule order.
- Preserve the existing `FormRuleEvaluator` temporal behavior; do not change cue timing or cooldown semantics except where tests require adapting to the new summary wrapper.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass using the default in-repo `.build`.
- Focused tests prove:
  - all passing active rules produce full score;
  - failed active rules reduce score according to `score_weight`;
  - inactive rules do not change the denominator;
  - invalid active rules follow the documented policy;
  - cue selection is deterministic by severity, then weight, then program order.
- At least one product-path integration test loads `Presets/bodyweight_squat.json`, processes timestamped synthetic frames through `FrameSignalProcessor`, `RepPredicateEvaluator`, `RepStateMachine`, `FormRuleEvaluator`, and the new score-summary path.
- Existing `ProgramLoaderTests`, `SignalEvaluatorTests`, `FilterPipelineTests`, `RepPredicateEvaluatorTests`, `RepStateMachineTests`, `SetProgressTrackerTests`, and `FormRuleEvaluatorTests` remain green or are intentionally updated to the score-summary contract.

## Expected Files

- `Sources/CamiFitEngine/FormRuleEvaluator.swift` or a new nearby form-summary source file.
- `Tests/CamiFitEngineTests/FormRuleEvaluatorTests.swift` or a new nearby form-summary test file.
- `docs/session-logs/014-executor-form-rule-score-summary.md`

Names may change if the implementation finds a cleaner local structure, but keep the score-summary boundary explicit.

## Validation Commands

```bash
cd /Users/kelly/Developer/camifit
swift build --disable-sandbox
swift test --disable-sandbox
```

## Evidence To Record

- `swift build --disable-sandbox` result.
- `swift test --disable-sandbox` test count and pass/fail.
- Printed focused score cases showing full score, weighted penalty, invalid policy, and cue priority.
- Printed product-path proof showing form snapshots plus score summary from the loaded squat preset.

## Reachability / Demo Proof

A test must load the real `Presets/bodyweight_squat.json`, process timestamped synthetic frames through `FrameSignalProcessor`, evaluate predicates through `RepPredicateEvaluator`, feed `RepStateMachine`, evaluate form rules from the resulting phase plus produced values and timestamps, and pass those snapshots through the new score-summary path.

Do not prove scoring only with hard-coded snapshots.

## Out Of Scope

- Per-rep score rollups, set-level mean score, post-set summary card, replay debugger, UI, audio, Python MediaPipe worker, camera, transport, model download, Layer 2, or Layer 3.
- Changing `min_violation_ms` or `cooldown_ms` semantics.
- Golden landmark fixtures and no-person acceptance gates.

## Stop Conditions

- ESCALATE before adding any remote dependency, network access, model download, Python worker, camera code, or Layer 2/3 behavior.
- STOP if `swift test --disable-sandbox` cannot run with the default in-repo `.build`; record the exact failure.
- Do not claim coaching accuracy or milestone completion from this slice. Per-rep/set rollups, replay, UI, pose fixtures, and no-person/low-visibility acceptance gates are still required later.
