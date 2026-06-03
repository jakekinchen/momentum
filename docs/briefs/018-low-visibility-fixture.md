# Slice Brief 018 - Low-Visibility Fixture

**Date:** 2026-06-03

## Objective

Add a second small checked-in synthetic fixture with a low-visibility/no-person-style interval and prove the existing fixture/trace path records invalid evidence without false counted reps.

Keep this pure Swift and offline: no MediaPipe, no Python worker, no camera, no network, no package dependencies.

## Product / Project Value

M1 requires exact rep counts and no false reps during no-person or low-visibility intervals. This slice is not the full golden gate; it establishes the next deterministic fixture case so invalid pose intervals are represented in durable test data and exercised through the real engine path.

## Scope

- Add one small checked-in synthetic fixture under `Tests/CamiFitEngineTests/Fixtures/`.
- Include at least one low-visibility interval that invalidates the configured squat phase signal or its source.
- Load the fixture through the existing `PoseFrameFixtureLoader`.
- Run fixture frames through `EngineTraceRecorder` and `EngineTraceFormatter` using `Presets/bodyweight_squat.json`.
- Assert invalid produced values and rep invalid reasons are retained in the trace/format output.
- Assert no rep is counted during the low-visibility interval.
- If the fixture includes valid movement before or after the invalid interval, make the expected rep count explicit and scoped.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass using the default in-repo `.build`.
- Focused tests prove:
  - the low-visibility fixture loads through `PoseFrameFixtureLoader`;
  - at least one trace frame records an invalid produced value for a relevant squat signal;
  - at least one trace frame records a rep invalid reason;
  - no frame inside the low-visibility interval has `countedThisFrame == true`;
  - formatted trace output includes the invalid produced value and rep invalid reason.
- Existing clean-fixture tests remain green.
- Existing `ProgramLoaderTests`, `SignalEvaluatorTests`, `FilterPipelineTests`, `RepPredicateEvaluatorTests`, `RepStateMachineTests`, `SetProgressTrackerTests`, `FormRuleEvaluatorTests`, `EngineTraceRecorderTests`, and `PoseFrameFixtureTests` remain green or are intentionally updated to the low-visibility fixture contract.

## Expected Files

- A new fixture JSON under `Tests/CamiFitEngineTests/Fixtures/`, for example `synthetic_squat_low_visibility_trace.json`.
- Focused fixture tests, likely in `Tests/CamiFitEngineTests/PoseFrameFixtureTests.swift`.
- `docs/session-logs/018-executor-low-visibility-fixture.md`

Names may change if the implementation finds a cleaner local structure, but keep the low-visibility fixture boundary explicit.

## Validation Commands

```bash
cd /Users/kelly/Developer/camifit
swift build --disable-sandbox
swift test --disable-sandbox
```

## Evidence To Record

- `swift build --disable-sandbox` result.
- `swift test --disable-sandbox` test count and pass/fail.
- Printed low-visibility fixture summary with frame count and invalid interval timestamps.
- Printed formatted invalid trace excerpt showing invalid produced value and rep invalid reason.
- Printed no-false-count evidence for the low-visibility interval.

## Reachability / Demo Proof

A test must load the checked-in low-visibility fixture JSON, convert it into `PoseFrame` values, run those values through `EngineTraceRecorder`, and format the resulting trace with `EngineTraceFormatter`.

Do not prove this only with hand-built `PoseFrame` values or direct `RepStateMachine` calls.

## Out Of Scope

- Real MediaPipe recording capture, Python worker, camera, file export beyond the checked-in test fixture, replay UI, plotting, live UI, audio, transport, model download, Layer 2, or Layer 3.
- The full golden no-person/low-visibility acceptance suite.
- Large fixture corpora or binary assets.
- Changing rep, form-rule, cooldown, scoring, trace-recording, trace-formatting, or fixture-loader semantics unless required by a clear fixture bug.

## Stop Conditions

- ESCALATE before adding any remote dependency, network access, model download, Python worker, camera code, large recording, or Layer 2/3 behavior.
- STOP if `swift test --disable-sandbox` cannot run with the default in-repo `.build`; record the exact failure.
- Do not claim coaching accuracy or milestone completion from this slice. Real recorded fixtures, full no-person/low-visibility gates, replay UI, and minimal live UI are still required later.
