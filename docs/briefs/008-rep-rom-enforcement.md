# Slice Brief 008 - Rep ROM Enforcement

**Date:** 2026-06-03

## Objective

Extend the squat `RepStateMachine` path to enforce the configured `RepConfig.min_rom_deg` using the configured `rep.phase_signal` value across an active rep attempt.

Keep this pure Swift and offline: no MediaPipe, no Python worker, no camera, no network, no package dependencies.

## Product / Project Value

Dwell timing now prevents a single noisy threshold crossing from counting as a rep. ROM enforcement is the next contract requirement: a rep should not count unless the observed phase signal moves through enough range while satisfying the timed down/bottom/up sequence.

## Scope

- Track ROM for the active rep attempt using produced values keyed by `rep.phase_signal`.
- Feed the phase-signal value into the state-machine update path, either directly or through a small update context that also carries timestamp and predicate results.
- Count a rep only when the timed sequence completes and the tracked phase-signal range satisfies `min_rom_deg`.
- Reset active ROM tracking after a counted rep or an aborted attempt.
- Preserve existing dwell-timing behavior and no-false-rep behavior for repeated standing, too-fast movement, shallow movement, and deep-start-before-ready.
- Invalid phase-signal / predicate frames must not count or corrupt ROM tracking. Preserve an explicit invalid reason.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass using the default in-repo `.build`.
- Loading `Presets/bodyweight_squat.json` and feeding a timestamped synthetic sequence through `FrameSignalProcessor`, `RepPredicateEvaluator`, and `RepStateMachine` proves:
  - a sequence that satisfies dwell timing and `min_rom_deg` counts exactly one rep;
  - a sequence that satisfies dwell timing but stays below `min_rom_deg` counts zero reps;
  - invalid phase-signal / invalid predicate frames do not count and do not corrupt ROM tracking.
- Existing `ProgramLoaderTests`, `SignalEvaluatorTests`, `FilterPipelineTests`, `RepPredicateEvaluatorTests`, and current `RepStateMachineTests` remain green or are intentionally updated to the ROM contract.

## Expected Files

- `Sources/CamiFitEngine/RepStateMachine.swift`
- `Tests/CamiFitEngineTests/RepStateMachineTests.swift`
- `docs/session-logs/008-executor-rep-rom-enforcement.md`

Names may change if the implementation finds a cleaner local structure, but keep the ROM state-machine boundary explicit.

## Validation Commands

```bash
cd /Users/kelly/Developer/camifit
swift build --disable-sandbox
swift test --disable-sandbox
```

## Evidence To Record

- `swift build --disable-sandbox` result.
- `swift test --disable-sandbox` test count and pass/fail.
- Printed timed valid sequence showing ROM range and one counted rep.
- Printed shallow / below-ROM sequence showing zero counted reps.
- Printed invalid-frame behavior showing no count and preserved invalid reason.

## Reachability / Demo Proof

A test must load the real `Presets/bodyweight_squat.json`, process timestamped synthetic frames through `FrameSignalProcessor`, evaluate predicates through `RepPredicateEvaluator`, read the configured phase-signal produced value, and feed the update into the state machine. Do not prove ROM enforcement only with hard-coded booleans.

## Out Of Scope

- Enforcing `cooldown_ms`.
- Set tracking, rest detection, hold evaluator, form rules, cue scoring, replay debugger, UI, audio, Python MediaPipe worker, camera, transport, model download, Layer 2, or Layer 3.
- Full `validity.phase_signal_invalid_policy` behavior such as freeze-then-reset. This slice only prevents invalid frames from counting or corrupting active ROM tracking.

## Stop Conditions

- ESCALATE before adding any remote dependency, network access, model download, Python worker, camera code, or Layer 2/3 behavior.
- STOP if `swift test --disable-sandbox` cannot run with the default in-repo `.build`; record the exact failure.
- Do not claim coaching accuracy or milestone completion from this slice. Golden landmark fixtures, cooldown, and no-person/low-visibility acceptance gates are still required later.
