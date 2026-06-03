# Slice Brief 016 - Engine Trace Formatting

**Date:** 2026-06-03

## Objective

Add deterministic text/table formatting for in-memory `EngineTraceFrame` records so tests and future replay/debugger work can inspect the trace without a UI or file export.

Keep this pure Swift and offline: no MediaPipe, no Python worker, no camera, no network, no package dependencies.

## Product / Project Value

The trace recorder now captures timestamped engine output. A stable formatter is the smallest next replay/debugger step: it gives reviewers and future UI work a predictable representation of phase, reps, signals, form cues, invalid reasons, and score changes.

## Scope

- Add a small formatter or formatting API for `[EngineTraceFrame]`.
- Produce deterministic text rows with stable columns, at minimum:
  - timestamp;
  - rep phase;
  - rep count;
  - counted-this-frame flag;
  - selected produced values;
  - active form rule summaries;
  - selected cue if present;
  - form score summary;
  - invalid reason when present.
- Ensure output ordering is deterministic and does not depend on dictionary iteration.
- Keep formatting in memory as `String` output only.
- Use the loaded squat preset and existing synthetic frames in tests.
- Preserve existing recorder, evaluator, FSM, form-rule, cooldown, and scoring semantics.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass using the default in-repo `.build`.
- Focused tests prove:
  - formatting is deterministic for repeated traces;
  - the output contains timestamp, phase, rep count, counted flag, selected produced values, form rules, cue/score fields, and invalid reason fields where applicable;
  - a counted-rep frame is visible in the formatted trace;
  - an invalid-frame trace includes the invalid produced value and rep invalid reason.
- At least one product-path integration test loads `Presets/bodyweight_squat.json`, records trace frames through `EngineTraceRecorder`, and formats those real trace frames.
- Existing `ProgramLoaderTests`, `SignalEvaluatorTests`, `FilterPipelineTests`, `RepPredicateEvaluatorTests`, `RepStateMachineTests`, `SetProgressTrackerTests`, `FormRuleEvaluatorTests`, and `EngineTraceRecorderTests` remain green or are intentionally updated to the formatting contract.

## Expected Files

- `Sources/CamiFitEngine/EngineTraceRecorder.swift` or a new nearby trace-formatting source file.
- `Tests/CamiFitEngineTests/EngineTraceRecorderTests.swift` or a new nearby trace-formatting test file.
- `docs/session-logs/016-executor-engine-trace-formatting.md`

Names may change if the implementation finds a cleaner local structure, but keep the trace-formatting boundary explicit.

## Validation Commands

```bash
cd /Users/kelly/Developer/camifit
swift build --disable-sandbox
swift test --disable-sandbox
```

## Evidence To Record

- `swift build --disable-sandbox` result.
- `swift test --disable-sandbox` test count and pass/fail.
- Printed formatted trace excerpt showing a normal counted-rep timeline.
- Printed formatted invalid-frame excerpt showing retained invalid evidence.

## Reachability / Demo Proof

A test must load the real `Presets/bodyweight_squat.json`, use `EngineTraceRecorder` on timestamped synthetic frames, and format the resulting real trace frames.

Do not prove formatting only with hand-built `EngineTraceFrame` fixtures.

## Out Of Scope

- File export, JSON trace schema, replay UI, plotting, live UI, audio, Python MediaPipe worker, camera, transport, model download, Layer 2, or Layer 3.
- Recorded landmark fixture collection.
- Golden no-person/low-visibility acceptance gates.
- Changing rep, form-rule, cooldown, scoring, or trace-recording semantics.

## Stop Conditions

- ESCALATE before adding any remote dependency, network access, model download, Python worker, camera code, or Layer 2/3 behavior.
- STOP if `swift test --disable-sandbox` cannot run with the default in-repo `.build`; record the exact failure.
- Do not claim coaching accuracy or milestone completion from this slice. Real fixtures, no-person/low-visibility gates, replay UI, and minimal live UI are still required later.
