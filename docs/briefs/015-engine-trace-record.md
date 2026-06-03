# Slice Brief 015 - Engine Trace Record

**Date:** 2026-06-03

## Objective

Add a deterministic Swift trace record for the existing engine product path. Each trace frame should capture enough timestamped output to inspect phase, reps, form snapshots, and form score summary from synthetic frames.

Keep this pure Swift and offline: no MediaPipe, no Python worker, no camera, no network, no package dependencies.

## Product / Project Value

M1 requires replay/debugger evidence before a polished UI. The current engine already produces signals, rep state, form cues, and score summaries; a trace record makes those outputs durable and inspectable without jumping to a graphical debugger, recorded landmark fixtures, or live camera.

## Scope

- Add a small trace model or recorder for one engine run over timestamped `PoseFrame` inputs.
- For each trace frame, capture at minimum:
  - `timestampMS`;
  - selected produced values needed for inspection, at least the rep phase signal and key squat signals;
  - `RepStateSnapshot` phase, rep count, counted-rep flag, invalid reason, and any cooldown/ROM evidence already exposed;
  - `[FormRuleSnapshot]`;
  - `FormRuleScoreSummary`.
- Provide deterministic ordering for any dictionary-derived fields.
- Keep the trace in memory; file export, JSON schema, UI plotting, and recorded fixtures are out of scope for this slice.
- Build the trace from the loaded squat preset and existing synthetic timestamped frames.
- Preserve existing evaluator, FSM, form-rule, and scoring semantics.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass using the default in-repo `.build`.
- Focused tests prove:
  - trace frames preserve input timestamps in order;
  - phase and rep count progress are captured from `RepStateMachine`;
  - form snapshots and score summaries are present on trace frames;
  - produced value keys are deterministic and include the configured phase signal plus key squat signals;
  - invalid produced values or invalid rep state are recorded rather than dropped.
- At least one product-path integration test loads `Presets/bodyweight_squat.json`, processes timestamped synthetic frames through `FrameSignalProcessor`, `RepPredicateEvaluator`, `RepStateMachine`, `FormRuleEvaluator`, `FormRuleScoreSummarizer`, and the new trace recorder.
- Existing `ProgramLoaderTests`, `SignalEvaluatorTests`, `FilterPipelineTests`, `RepPredicateEvaluatorTests`, `RepStateMachineTests`, `SetProgressTrackerTests`, and `FormRuleEvaluatorTests` remain green or are intentionally updated to the trace contract.

## Expected Files

- A new source file near the engine code, such as `Sources/CamiFitEngine/EngineTraceRecorder.swift`, or a local equivalent if the implementation finds a clearer fit.
- A focused test file or nearby existing test updates, such as `Tests/CamiFitEngineTests/EngineTraceRecorderTests.swift`.
- `docs/session-logs/015-executor-engine-trace-record.md`

Names may change if the implementation finds a cleaner local structure, but keep the trace-record boundary explicit.

## Validation Commands

```bash
cd /Users/kelly/Developer/camifit
swift build --disable-sandbox
swift test --disable-sandbox
```

## Evidence To Record

- `swift build --disable-sandbox` result.
- `swift test --disable-sandbox` test count and pass/fail.
- Printed trace excerpt showing timestamp, phase, rep count, selected produced values, form snapshots, and score summary.
- Printed invalid-frame trace evidence if covered by a focused test.

## Reachability / Demo Proof

A test must load the real `Presets/bodyweight_squat.json`, process timestamped synthetic frames through the same product path used by previous slices, and emit trace frames from those real engine outputs.

Do not prove trace recording only with hard-coded snapshots or hand-built rep states.

## Out Of Scope

- File export, JSON trace schema, replay UI, plotting, live UI, audio, Python MediaPipe worker, camera, transport, model download, Layer 2, or Layer 3.
- Recorded landmark fixture collection.
- Golden no-person/low-visibility acceptance gates.
- Changing rep, form-rule, cooldown, or scoring semantics.

## Stop Conditions

- ESCALATE before adding any remote dependency, network access, model download, Python worker, camera code, or Layer 2/3 behavior.
- STOP if `swift test --disable-sandbox` cannot run with the default in-repo `.build`; record the exact failure.
- Do not claim coaching accuracy or milestone completion from this slice. Replay UI, real fixtures, no-person/low-visibility gates, and minimal live UI are still required later.
