# Slice Brief 004 - Filter pipeline + produced signal table

**Date:** 2026-06-03

## Objective

Add the stateful filter runtime for Exercise-Program `filters` and expose a produced signal table containing both raw signal values and filtered values. This connects the already-working raw `SignalEvaluator` to the contract names used by later rep/form predicates (`knee`, `torso_tilt`).

Keep this pure Swift and offline: no MediaPipe, no Python worker, no camera, no network, no package dependencies.

## Product / Project Value

The squat program's rep and form rules intentionally reference filtered outputs, not raw per-frame signals. A deterministic `FilterPipeline` is the next engine component needed before evaluating `rep.down_when`, `rep.up_when`, or temporal form rules.

## Scope

- Add a `FilterPipeline` or equivalently named type that is initialized from an `ExerciseProgram`.
- Support the two filter types already in the contract:
  - `ema` using `alpha`;
  - `median` using `window_ms` and frame `timestampMS`.
- Add an engine-facing method that, for each frame, returns a combined produced-value table:
  - raw signals from `SignalEvaluator`;
  - filtered outputs from `program.filters`, keyed by filter name.
- Filter source values must come from the raw signal table for this slice. Do not allow filters to depend on other filters unless a later brief explicitly adds and validates that behavior.
- Define and test invalid-input policy:
  - invalid source input produces an invalid filtered value naming the source reason;
  - invalid source input must not silently update filter state with a numeric placeholder.
- Define and test confidence propagation for filtered values. Keep the policy simple and deterministic.
- Preserve deterministic behavior across repeated runs with the same frame sequence.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass using the default in-repo `.build`.
- EMA is tested on a timestamped numeric sequence with exact expected outputs for a known alpha.
- Median is tested on a timestamped numeric sequence with samples entering and leaving the `window_ms` interval; the test states the even-count median policy explicitly.
- Invalid raw source values produce invalid filtered outputs and do not corrupt later valid outputs.
- Loading `Presets/bodyweight_squat.json`, evaluating a synthetic standing frame, and running filters produces a stable table containing:
  - raw values: `knee_left`, `knee_right`, `knee_raw`, `torso_raw`, `knee_symmetry`;
  - filtered values: `knee`, `torso_tilt`.
- Existing `ProgramLoaderTests` and `SignalEvaluatorTests` remain green.

## Expected Files

- `Sources/CamiFitEngine/FilterPipeline.swift`
- `Sources/CamiFitEngine/FrameSignalProcessor.swift` or another small integration type if needed
- `Tests/CamiFitEngineTests/FilterPipelineTests.swift`
- `docs/session-logs/004-executor-filter-pipeline-produced-values.md`

Names may change if the implementation finds a cleaner local structure, but keep the filter boundary explicit.

## Validation Commands

```bash
cd /Users/kelly/Developer/camifit
swift build --disable-sandbox
swift test --disable-sandbox
```

## Evidence To Record

- `swift build --disable-sandbox` result.
- `swift test --disable-sandbox` test count and pass/fail.
- Printed EMA sequence output.
- Printed median window output, including the even-count median policy.
- Printed produced-value table for the real squat preset on a synthetic standing frame.
- Printed invalid-source filter output.

## Reachability / Demo Proof

A test must load the real `Presets/bodyweight_squat.json`, evaluate a synthetic standing `PoseFrame`, run the filters, and print the produced-value table including both raw and filtered names. Do not prove filters only with standalone literals.

## Out Of Scope

- Predicate/comparison evaluation for `rep.down_when`, `rep.up_when`, `hold.in_range`, or `form_rules`.
- Validity timing policy such as `freeze_then_reset`.
- Rep/hold/set state machines, cue scoring, replay debugger, UI, audio, Python MediaPipe worker, camera, transport, model download, Layer 2, or Layer 3.
- Filter-to-filter dependencies.

## Stop Conditions

- ESCALATE before adding any remote dependency, network access, model download, Python worker, camera code, or Layer 2/3 behavior.
- STOP if `swift test --disable-sandbox` cannot run with the default in-repo `.build`; record the exact failure.
- Do not weaken existing load-time validation or allow invalid programs to reach runtime.
