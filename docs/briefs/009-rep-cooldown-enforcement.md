# Slice Brief 009 - Rep Cooldown Enforcement

**Date:** 2026-06-03

## Objective

Extend the squat `RepStateMachine` to enforce `RepConfig.cooldownMS` after a counted rep so repeated up / ready frames cannot double-count the same movement.

Keep this pure Swift and offline: no MediaPipe, no Python worker, no camera, no network, no package dependencies.

## Product / Project Value

The rep FSM now enforces predicate hysteresis, dwell timing, and ROM. Cooldown enforcement completes the configured rep-counting guardrails before the milestone moves outward to set tracking and form-rule evaluation.

## Scope

- Track the timestamp of the last counted rep or an explicit cooldown-until timestamp.
- Prevent new rep attempts from starting or counting until `cooldown_ms` has elapsed after a counted rep.
- Preserve existing dwell, ROM, no-false-rep, and invalid-frame behavior.
- Keep cooldown local to the rep FSM; do not introduce set tracking, rest detection, form rules, UI, or replay artifacts.
- Keep `RepStateSnapshot` evidence sufficient to prove cooldown behavior, either by adding a small cooldown field or by printing a clear phase/count timeline.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass using the default in-repo `.build`.
- Loading `Presets/bodyweight_squat.json` and feeding timestamped synthetic frames through `FrameSignalProcessor`, `RepPredicateEvaluator`, and `RepStateMachine` proves:
  - the existing valid timed + ROM sequence still counts exactly one rep;
  - a second threshold-crossing sequence inside `cooldown_ms` after the first counted rep does not count;
  - a second valid sequence after cooldown elapsed can count exactly one additional rep;
  - invalid frames during cooldown do not count and do not corrupt the later valid attempt.
- Existing `ProgramLoaderTests`, `SignalEvaluatorTests`, `FilterPipelineTests`, `RepPredicateEvaluatorTests`, and current `RepStateMachineTests` remain green or are intentionally updated to the cooldown contract.

## Expected Files

- `Sources/CamiFitEngine/RepStateMachine.swift`
- `Tests/CamiFitEngineTests/RepStateMachineTests.swift`
- `docs/session-logs/009-executor-rep-cooldown-enforcement.md`

Names may change if the implementation finds a cleaner local structure, but keep the cooldown state-machine boundary explicit.

## Validation Commands

```bash
cd /Users/kelly/Developer/camifit
swift build --disable-sandbox
swift test --disable-sandbox
```

## Evidence To Record

- `swift build --disable-sandbox` result.
- `swift test --disable-sandbox` test count and pass/fail.
- Printed timeline showing one counted rep, blocked in-cooldown movement, then one later counted rep after cooldown.
- Printed invalid-frame behavior during cooldown.

## Reachability / Demo Proof

A test must load the real `Presets/bodyweight_squat.json`, process timestamped synthetic frames through `FrameSignalProcessor`, evaluate predicates through `RepPredicateEvaluator`, read the configured phase-signal produced value, and feed the update into the state machine. Do not prove cooldown only with hard-coded booleans.

## Out Of Scope

- Set tracking, rest detection, hold evaluator, form rules, cue scoring, replay debugger, UI, audio, Python MediaPipe worker, camera, transport, model download, Layer 2, or Layer 3.
- Full `validity.phase_signal_invalid_policy` behavior such as freeze-then-reset.
- Golden landmark fixtures and no-person acceptance gates.

## Stop Conditions

- ESCALATE before adding any remote dependency, network access, model download, Python worker, camera code, or Layer 2/3 behavior.
- STOP if `swift test --disable-sandbox` cannot run with the default in-repo `.build`; record the exact failure.
- Do not claim coaching accuracy or milestone completion from this slice. Golden landmark fixtures, set/form behavior, and no-person/low-visibility acceptance gates are still required later.
