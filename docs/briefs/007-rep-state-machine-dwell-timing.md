# Slice Brief 007 - Rep state-machine dwell timing

**Date:** 2026-06-03

## Objective

Extend the basic squat `RepStateMachine` to enforce the configured dwell timings from `RepConfig`: `down_min_ms`, `bottom_min_ms`, and `up_min_ms`, using frame timestamps from the product path.

Keep this pure Swift and offline: no MediaPipe, no Python worker, no camera, no network, no package dependencies.

## Product / Project Value

The engine can now count a simple down/up pattern, but the approved contract requires temporal validation so a single noisy threshold crossing cannot count as a rep. Dwell timing is the next step toward trustworthy fixture-based rep counts.

## Scope

- Add timestamp input to the rep state-machine update path, either directly or through a small frame/update context.
- Enforce:
  - `down_min_ms`: down predicate must remain satisfied long enough before the machine can accept the down phase;
  - `bottom_min_ms`: the down/bottom state must persist long enough before an up transition can count;
  - `up_min_ms`: up predicate must remain satisfied long enough before a rep is counted.
- Expand phases if needed, for example `seeking_ready`, `ready`, `descending`, `bottom`, `ascending`.
- Preserve the existing basic no-false-rep behavior for repeated standing, shallow movement, and deep-start-before-ready.
- Invalid predicate frames must not count or advance dwell timers. Preserve an explicit invalid reason.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass using the default in-repo `.build`.
- Loading `Presets/bodyweight_squat.json` and feeding a timestamped synthetic sequence through `FrameSignalProcessor`, `RepPredicateEvaluator`, and `RepStateMachine` proves:
  - a sequence that satisfies `down_min_ms`, `bottom_min_ms`, and `up_min_ms` counts exactly one rep;
  - a too-fast down/up sequence that crosses thresholds but fails dwell timing counts zero reps;
  - repeated standing, shallow movement, and deep-start-before-ready still count zero reps.
- Invalid `knee` / invalid predicate frames do not count and do not advance dwell timers.
- Existing `ProgramLoaderTests`, `SignalEvaluatorTests`, `FilterPipelineTests`, `RepPredicateEvaluatorTests`, and current `RepStateMachineTests` remain green or are intentionally updated to the timed contract.

## Expected Files

- `Sources/CamiFitEngine/RepStateMachine.swift`
- `Tests/CamiFitEngineTests/RepStateMachineTests.swift`
- `docs/session-logs/007-executor-rep-state-machine-dwell-timing.md`

Names may change if the implementation finds a cleaner local structure, but keep the timed state-machine boundary explicit.

## Validation Commands

```bash
cd /Users/kelly/Developer/camifit
swift build --disable-sandbox
swift test --disable-sandbox
```

## Evidence To Record

- `swift build --disable-sandbox` result.
- `swift test --disable-sandbox` test count and pass/fail.
- Printed timed phase/rep timeline for the valid sequence.
- Printed too-fast no-count timeline.
- Printed invalid-frame timing behavior.

## Reachability / Demo Proof

A test must load the real `Presets/bodyweight_squat.json`, process timestamped synthetic frames through `FrameSignalProcessor`, evaluate predicates through `RepPredicateEvaluator`, and feed timestamped updates into the state machine. Do not prove dwell timing only with hard-coded booleans.

## Out Of Scope

- Enforcing `min_rom_deg` and `cooldown_ms`.
- Set tracking, rest detection, hold evaluator, form rules, cue scoring, replay debugger, UI, audio, Python MediaPipe worker, camera, transport, model download, Layer 2, or Layer 3.
- Full `validity.phase_signal_invalid_policy` behavior such as freeze-then-reset. This slice only prevents invalid frames from advancing timers or counting.

## Stop Conditions

- ESCALATE before adding any remote dependency, network access, model download, Python worker, camera code, or Layer 2/3 behavior.
- STOP if `swift test --disable-sandbox` cannot run with the default in-repo `.build`; record the exact failure.
- Do not claim coaching accuracy or milestone completion from this slice. Golden landmark fixtures, ROM/cooldown, and no-person/low-visibility acceptance gates are still required later.
