# Slice Brief 003 - PoseFrame + core signal evaluator

**Date:** 2026-06-03

## Objective

Implement the first runtime evaluator increment for Layer 1: a minimal `PoseFrame` / landmark model, `SignalValue`, and a sandboxed expression parser/evaluator sufficient to evaluate the real squat preset's raw `signals` (`angle`, `angle_to_vertical`, `abs`, arithmetic, named signal dependencies) against synthetic pose frames.

This continues brief 002 after the calibration-reference sub-slice. Keep it pure Swift and offline: no MediaPipe, no Python worker, no camera, no network, no package dependencies.

## Product / Project Value

The exercise engine cannot count reps or score form until program signals evaluate deterministically from pose landmarks. This slice proves the contract can move from load-time validation to actual numeric signal values while preserving total, sandboxed semantics.

## Scope

- Add a small pose input model for tests and future engine use:
  - timestamp in milliseconds;
  - image size or dimensions;
  - named landmarks addressable as `left.<name>`, `right.<name>`, and `primary.<name>`;
  - landmark values include `x`, `y`, `z`, `visibility`, and `presence`.
- Add `SignalValue` with at least:
  - valid numeric value plus confidence;
  - invalid value with a reason string.
- Add a parser/AST/evaluator for this slice's numeric subset:
  - numeric literals;
  - named signal references;
  - landmark references used as function arguments;
  - `+`, `-`, `*`, `/` with safe divide;
  - function calls for `angle(a,b,c)`, `angle_to_vertical(a,b)`, and `abs(x)`.
- Evaluate raw program `signals` in dependency order so `knee_symmetry = abs(knee_left - knee_right)` can consume earlier computed signals.
- Apply `program.validity.minSignalConfidence` by combining landmark visibility/presence; any dependent signal must become invalid with a reason naming the offending landmark when required landmarks are below threshold.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass using the default in-repo `.build`.
- Loading `Presets/bodyweight_squat.json` and evaluating its raw signals against a synthetic standing pose produces deterministic values:
  - `knee_left`, `knee_right`, and `knee_raw` near the expected straight-leg angle;
  - `torso_raw` near the expected vertical torso angle;
  - `knee_symmetry` equals `abs(knee_left - knee_right)` within tolerance.
- Low visibility or presence for a required landmark invalidates only dependent signals, and the invalid reason names that landmark.
- Safe divide or degenerate geometry returns `invalid`, never crashes and never silently propagates NaN/Inf as valid.
- Evaluation is deterministic: same program + frame produces equal `SignalValue` tables.
- Existing `ProgramLoaderTests` remain green.

## Expected Files

- `Sources/CamiFitEngine/PoseFrame.swift`
- `Sources/CamiFitEngine/SignalValue.swift`
- `Sources/CamiFitEngine/Expression/AST.swift`
- `Sources/CamiFitEngine/Expression/Lexer.swift`
- `Sources/CamiFitEngine/Expression/Parser.swift`
- `Sources/CamiFitEngine/Expression/Evaluator.swift`
- `Sources/CamiFitEngine/SignalEvaluator.swift`
- `Tests/CamiFitEngineTests/SignalEvaluatorTests.swift`
- `docs/session-logs/003-executor-poseframe-signal-evaluator-core.md`

Names may change if the implementation finds a cleaner local structure, but keep the boundary explicit.

## Validation Commands

```bash
cd /Users/kelly/Developer/camifit
swift build --disable-sandbox
swift test --disable-sandbox
```

## Evidence To Record

- `swift build --disable-sandbox` result.
- `swift test --disable-sandbox` test count and pass/fail.
- Printed evaluated squat signal table for the synthetic standing pose.
- Printed invalid low-visibility reason.
- Printed safe-divide or degenerate-geometry invalid result.

## Reachability / Demo Proof

A test must load the real `Presets/bodyweight_squat.json`, evaluate its `signals` through the new evaluator against a synthetic standing `PoseFrame`, and print a stable signal table. Do not use only unit-test expression literals.

## Out Of Scope

- Comparisons, boolean operators, `in`, `between`, string/list literals, and state variables except where a tiny parser placeholder is needed.
- Evaluating `rep.down_when`, `rep.up_when`, `hold.in_range`, or `form_rules`.
- Filter runtime (`ema`, `median`), validity-gate timing policy, rep/hold/set state machines, cue scoring, or replay debugger.
- Python MediaPipe worker, `PoseProvider`, camera, transport, model download, UI, audio, Layer 2, or Layer 3.

## Stop Conditions

- ESCALATE before adding any remote dependency, network access, model download, Python worker, camera code, or Layer 2/3 behavior.
- STOP if `swift test --disable-sandbox` cannot run with the default in-repo `.build`; record the exact failure.
- Keep the evaluator total and allowlisted. Do not add arbitrary code execution, assignment, statements, loops, IO, reflection, or dynamic function dispatch.
