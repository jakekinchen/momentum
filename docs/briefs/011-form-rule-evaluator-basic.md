# Slice Brief 011 - Basic Form Rule Evaluator

**Date:** 2026-06-03

## Objective

Add the smallest pure Swift form-rule evaluator that loads the squat preset's `form_rules`, evaluates each rule's `when` and `expect` predicates against produced signal values plus current rep phase, and emits deterministic per-frame rule snapshots.

Keep this pure Swift and offline: no MediaPipe, no Python worker, no camera, no network, no package dependencies.

## Product / Project Value

The engine can now count reps and track set progress. The next M1 layer is form checking: the loaded program's rules must be executable by the same deterministic contract before cue timing, scoring, replay, or UI can depend on them.

## Scope

- Add a small `FormRuleEvaluator` or equivalent local engine type.
- Initialize from `ExerciseProgram` / `form_rules`.
- Evaluate loaded preset rule predicates against:
  - produced values from `FrameSignalProcessor`;
  - the current `RepPhase`;
  - optionally current rep count / time-in-phase only if needed by local structure.
- Add only the narrow expression/predicate support needed for the current squat preset form rules:
  - numeric comparisons such as `knee <= 95`;
  - phase equality such as `phase == 'bottom'`;
  - phase membership such as `phase in ['descending','bottom']`.
- Emit a deterministic snapshot per rule, including rule id, whether the rule is active, whether the expectation passes, optional violation/cue text, severity, and any invalid reason.
- Invalid/missing signal inputs should not crash and should produce a skipped/invalid rule snapshot rather than a violation.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass using the default in-repo `.build`.
- Loading `Presets/bodyweight_squat.json` proves all three bundled form rules are parsed/initialized.
- Focused tests prove:
  - `depth` is active at `.bottom` and emits the configured `"Go deeper"` cue when `knee > 95`;
  - `depth` passes at `.bottom` when `knee <= 95`;
  - `torso` is active during `.descending` or `.bottom` and inactive during `.ready`;
  - invalid/missing produced values skip or invalidate the affected rule without crashing.
- At least one product-path integration test processes synthetic frames through `FrameSignalProcessor`, `RepPredicateEvaluator`, `RepStateMachine`, and `FormRuleEvaluator` to show a form-rule snapshot reachable from the loaded preset.
- Existing `ProgramLoaderTests`, `SignalEvaluatorTests`, `FilterPipelineTests`, `RepPredicateEvaluatorTests`, `RepStateMachineTests`, and `SetProgressTrackerTests` remain green or are intentionally updated to the form-rule contract.

## Expected Files

- `Sources/CamiFitEngine/FormRuleEvaluator.swift` or a similarly named local engine file.
- Expression parser/evaluator files only if needed for the narrow phase/string/list predicate support above.
- `Tests/CamiFitEngineTests/FormRuleEvaluatorTests.swift` or focused additions to an existing test file.
- `docs/session-logs/011-executor-form-rule-evaluator-basic.md`

Names may change if the implementation finds a cleaner local structure, but keep the form-rule evaluator boundary explicit.

## Validation Commands

```bash
cd /Users/kelly/Developer/camifit
swift build --disable-sandbox
swift test --disable-sandbox
```

## Evidence To Record

- `swift build --disable-sandbox` result.
- `swift test --disable-sandbox` test count and pass/fail.
- Printed focused rule snapshots for active/pass/fail/inactive/invalid cases.
- Printed product-path proof showing loaded preset form-rule snapshots from synthetic frames.

## Reachability / Demo Proof

A test must load the real `Presets/bodyweight_squat.json`, process timestamped synthetic frames through `FrameSignalProcessor`, evaluate predicates through `RepPredicateEvaluator`, feed `RepStateMachine`, and evaluate form rules from the resulting phase plus produced values. Do not prove form rules only with hard-coded booleans.

## Out Of Scope

- Temporal `min_violation_ms` persistence.
- Form-rule `cooldown_ms` cue throttling.
- Weighted scoring or post-set summary.
- Replay debugger, UI, audio, Python MediaPipe worker, camera, transport, model download, Layer 2, or Layer 3.
- Golden landmark fixtures and no-person acceptance gates.

## Stop Conditions

- ESCALATE before adding any remote dependency, network access, model download, Python worker, camera code, or Layer 2/3 behavior.
- STOP if `swift test --disable-sandbox` cannot run with the default in-repo `.build`; record the exact failure.
- Do not claim coaching accuracy or milestone completion from this slice. Temporal cue behavior, scoring, replay, UI, pose fixtures, and no-person/low-visibility acceptance gates are still required later.
