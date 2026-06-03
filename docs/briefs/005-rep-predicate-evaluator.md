# Slice Brief 005 - Rep predicate evaluator

**Date:** 2026-06-03

## Objective

Add boolean predicate evaluation for the squat preset's rep thresholds: `rep.down_when` and `rep.up_when` over the produced-value table emitted by `FrameSignalProcessor`.

This is not the rep state machine yet. It is the predicate layer the state machine will call.

Keep this pure Swift and offline: no MediaPipe, no Python worker, no camera, no network, no package dependencies.

## Product / Project Value

The engine can now produce filtered signal names such as `knee` and `torso_tilt`. The next step is to evaluate the program's threshold predicates against those produced values so later slices can implement phase transitions, dwell timing, ROM, and cooldown without embedding threshold logic in the state machine.

## Scope

- Extend the expression parser/evaluator or add a small predicate evaluator that supports numeric comparisons:
  - `<`, `<=`, `>`, `>=`, `==`, `!=`.
- Evaluate `rep.down_when` and `rep.up_when` against a produced-value table containing raw and filtered `SignalValue`s.
- Return an explicit predicate result type, for example:
  - `true`;
  - `false`;
  - `invalid(reason:)`.
- Invalid or missing source signals must produce `invalid`, not `false`.
- Preserve the existing numeric expression behavior for signal evaluation.
- Keep unsupported DSL features outside this slice explicit and fail-closed.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass using the default in-repo `.build`.
- Loading `Presets/bodyweight_squat.json`, processing synthetic frames through `FrameSignalProcessor`, and evaluating rep predicates proves:
  - standing pose with `knee` near 180 makes `rep.up_when` true and `rep.down_when` false;
  - deep-squat pose with `knee` below the configured threshold makes `rep.down_when` true and `rep.up_when` false.
- Invalid produced values for `knee` make both rep predicates invalid with a reason naming `knee`.
- Missing produced values make predicates invalid with a precise missing-signal reason.
- Existing `ProgramLoaderTests`, `SignalEvaluatorTests`, and `FilterPipelineTests` remain green.

## Expected Files

- `Sources/CamiFitEngine/Expression/AST.swift`
- `Sources/CamiFitEngine/Expression/Lexer.swift`
- `Sources/CamiFitEngine/Expression/Parser.swift`
- `Sources/CamiFitEngine/Expression/Evaluator.swift`
- `Sources/CamiFitEngine/RepPredicateEvaluator.swift` or equivalent
- `Tests/CamiFitEngineTests/RepPredicateEvaluatorTests.swift`
- `docs/session-logs/005-executor-rep-predicate-evaluator.md`

Names may change if the implementation finds a cleaner local structure, but keep the predicate boundary explicit.

## Validation Commands

```bash
cd /Users/kelly/Developer/camifit
swift build --disable-sandbox
swift test --disable-sandbox
```

## Evidence To Record

- `swift build --disable-sandbox` result.
- `swift test --disable-sandbox` test count and pass/fail.
- Printed predicate results for standing and deep-squat synthetic frames.
- Printed invalid-predicate reason for invalid or missing `knee`.

## Reachability / Demo Proof

A test must load the real `Presets/bodyweight_squat.json`, process synthetic frames through `FrameSignalProcessor`, and evaluate the real `rep.down_when` / `rep.up_when` strings from the loaded program. Do not prove this only with literal test predicates.

## Out Of Scope

- Rep phase state machine, dwell timers, ROM, cooldown, rep counting, or set tracking.
- Boolean `and` / `or` / `not`, membership `in`, `between`, string/list literals, and state variables such as `phase` unless needed as a fail-closed parse case.
- `hold.in_range` and `form_rules`.
- Validity timing policy such as `freeze_then_reset`.
- Python MediaPipe worker, `PoseProvider`, camera, transport, model download, replay debugger, UI, audio, Layer 2, or Layer 3.

## Stop Conditions

- ESCALATE before adding any remote dependency, network access, model download, Python worker, camera code, or Layer 2/3 behavior.
- STOP if `swift test --disable-sandbox` cannot run with the default in-repo `.build`; record the exact failure.
- Keep the predicate evaluator total and fail-closed. Do not add arbitrary code execution, assignment, statements, loops, IO, reflection, or dynamic function dispatch.
