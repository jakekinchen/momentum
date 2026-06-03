# Slice Brief 017 - PoseFrame Fixture Harness

**Date:** 2026-06-03

## Objective

Add a repo-local fixture container for deterministic `PoseFrame` sequences and use it to run the existing squat trace recorder/formatter against one checked-in synthetic squat fixture.

Keep this pure Swift and offline: no MediaPipe, no Python worker, no camera, no network, no package dependencies.

## Product / Project Value

M1 ultimately requires recorded landmark fixtures with exact rep-count and no-person/low-visibility gates. This slice does not collect real recordings yet; it creates the durable fixture harness shape using synthetic pose frames so subsequent real fixture work has a tested loading path.

## Scope

- Add one checked-in synthetic squat fixture under the existing test fixture area, such as `Tests/CamiFitEngineTests/Fixtures/`.
- Define a minimal fixture schema for timestamped `PoseFrame` sequences:
  - image width/height;
  - timestamp per frame;
  - landmark id map with x/y/z/visibility/presence.
- Add a Swift fixture loader that parses the checked-in fixture into `[PoseFrame]`.
- Run loaded fixture frames through `EngineTraceRecorder` and `EngineTraceFormatter` using `Presets/bodyweight_squat.json`.
- Assert the same product-path expectations currently proven by generated synthetic frames: at least one counted rep, bottom-phase form snapshots/score, and deterministic formatted output.
- Keep the fixture small and readable; do not add large recordings or generated binary artifacts.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass using the default in-repo `.build`.
- Focused tests prove:
  - the fixture loader preserves frame timestamps and image dimensions;
  - required squat landmarks are loaded with visibility/presence;
  - the loaded fixture records at least one counted rep through `EngineTraceRecorder`;
  - the formatted trace from loaded fixture frames is deterministic and includes the counted-rep row;
  - active form snapshots and score summary are present on a bottom frame.
- Existing `ProgramLoaderTests`, `SignalEvaluatorTests`, `FilterPipelineTests`, `RepPredicateEvaluatorTests`, `RepStateMachineTests`, `SetProgressTrackerTests`, `FormRuleEvaluatorTests`, and `EngineTraceRecorderTests` remain green or are intentionally updated to the fixture-harness contract.

## Expected Files

- A new fixture JSON under `Tests/CamiFitEngineTests/Fixtures/`, for example `synthetic_squat_clean_trace.json`.
- A fixture loader source in tests or engine code, depending on the local fit; prefer test support if it is only for tests.
- A focused test file or nearby existing test updates, such as `Tests/CamiFitEngineTests/EngineTraceRecorderTests.swift` or `Tests/CamiFitEngineTests/PoseFrameFixtureTests.swift`.
- `docs/session-logs/017-executor-poseframe-fixture-harness.md`

Names may change if the implementation finds a cleaner local structure, but keep the fixture-harness boundary explicit.

## Validation Commands

```bash
cd /Users/kelly/Developer/camifit
swift build --disable-sandbox
swift test --disable-sandbox
```

## Evidence To Record

- `swift build --disable-sandbox` result.
- `swift test --disable-sandbox` test count and pass/fail.
- Printed fixture summary with frame count and first/last timestamps.
- Printed formatted trace excerpt showing the counted-rep row from loaded fixture frames.
- Printed bottom-frame form/score evidence from loaded fixture frames.

## Reachability / Demo Proof

A test must load the checked-in fixture JSON, convert it into `PoseFrame` values, run those values through `EngineTraceRecorder`, and format the resulting trace with `EngineTraceFormatter`.

Do not prove fixture loading only by checking JSON fields without running the engine path.

## Out Of Scope

- Real MediaPipe recording capture, Python worker, camera, file export beyond the checked-in test fixture, replay UI, plotting, live UI, audio, transport, model download, Layer 2, or Layer 3.
- Golden no-person/low-visibility acceptance gates.
- Large fixture corpora or binary assets.
- Changing rep, form-rule, cooldown, scoring, trace-recording, or trace-formatting semantics.

## Stop Conditions

- ESCALATE before adding any remote dependency, network access, model download, Python worker, camera code, large recording, or Layer 2/3 behavior.
- STOP if `swift test --disable-sandbox` cannot run with the default in-repo `.build`; record the exact failure.
- Do not claim coaching accuracy or milestone completion from this slice. Real recorded fixtures, no-person/low-visibility gates, replay UI, and minimal live UI are still required later.
