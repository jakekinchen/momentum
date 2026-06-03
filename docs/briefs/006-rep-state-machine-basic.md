# Slice Brief 006 - Basic rep state machine

**Date:** 2026-06-03

## Objective

Implement the first `RepStateMachine` increment for the squat vertical: consume produced signal tables plus `RepPredicateEvaluator` results and move through the basic phase path needed to count one squat rep.

This slice proves the engine can turn filtered signals and predicates into deterministic rep events. It is still not the full production rep engine.

Keep this pure Swift and offline: no MediaPipe, no Python worker, no camera, no network, no package dependencies.

## Product / Project Value

The contract now loads, raw signals evaluate, filters publish produced values, and rep predicates evaluate. The next milestone step is to count a simple down/up squat sequence through a state machine instead of isolated predicates.

## Scope

- Add `RepStateMachine` or equivalently named type initialized from `ExerciseProgram.rep`.
- Add a small result/snapshot type that exposes at least:
  - current phase;
  - rep count;
  - whether a rep was counted on the current frame;
  - optional invalid reason for the current frame.
- Support the minimal phase sequence:
  - standing/ready starts with `up_when == true`;
  - `down_when == true` enters a down/bottom phase;
  - `up_when == true` after a down phase counts one rep and returns to ready/up.
- Consume produced values from `FrameSignalProcessor` and predicate results from `RepPredicateEvaluator`.
- Invalid predicate results must not count reps. Preserve an explicit invalid reason in the snapshot.
- Avoid double counting when the user stays up or stays down across repeated frames.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass using the default in-repo `.build`.
- Loading `Presets/bodyweight_squat.json` and feeding a synthetic sequence through `FrameSignalProcessor` plus the new state machine proves:
  - standing -> deep -> standing counts exactly one rep;
  - repeated standing frames count zero reps;
  - standing -> shallow/not-down -> standing counts zero reps;
  - deep -> standing without first establishing ready/up does not produce a false rep unless the state machine explicitly defines that as a valid start state and tests the behavior.
- Invalid `knee` / invalid predicate frames do not count reps and surface a reason naming `knee`.
- Existing `ProgramLoaderTests`, `SignalEvaluatorTests`, `FilterPipelineTests`, and `RepPredicateEvaluatorTests` remain green.

## Expected Files

- `Sources/CamiFitEngine/RepStateMachine.swift`
- `Tests/CamiFitEngineTests/RepStateMachineTests.swift`
- `docs/session-logs/006-executor-rep-state-machine-basic.md`

Names may change if the implementation finds a cleaner local structure, but keep the state-machine boundary explicit.

## Validation Commands

```bash
cd /Users/kelly/Developer/camifit
swift build --disable-sandbox
swift test --disable-sandbox
```

## Evidence To Record

- `swift build --disable-sandbox` result.
- `swift test --disable-sandbox` test count and pass/fail.
- Printed phase/rep timeline for the standing -> deep -> standing sequence.
- Printed no-false-rep timeline for repeated standing and shallow sequences.
- Printed invalid-frame snapshot for invalid `knee`.

## Reachability / Demo Proof

A test must load the real `Presets/bodyweight_squat.json`, process synthetic frames through `FrameSignalProcessor`, evaluate predicates through `RepPredicateEvaluator`, and feed those results into the state machine. Do not prove the state machine only with hard-coded booleans.

## Out Of Scope

- Enforcing `down_min_ms`, `bottom_min_ms`, `up_min_ms`, `cooldown_ms`, and `min_rom_deg`.
- Set tracking, rest detection, hold evaluator, form rules, cue scoring, replay debugger, UI, audio, Python MediaPipe worker, camera, transport, model download, Layer 2, or Layer 3.
- Full `validity.phase_signal_invalid_policy` timing such as `freeze_then_reset`; this slice only records invalid frames and avoids counting through them.

## Stop Conditions

- ESCALATE before adding any remote dependency, network access, model download, Python worker, camera code, or Layer 2/3 behavior.
- STOP if `swift test --disable-sandbox` cannot run with the default in-repo `.build`; record the exact failure.
- Do not claim coaching accuracy or milestone completion from this slice. Golden landmark fixtures and full timing gates are still required later.
