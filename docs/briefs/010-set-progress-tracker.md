# Slice Brief 010 - Set Progress Tracker

**Date:** 2026-06-03

## Objective

Add the smallest pure Swift set-progress tracker that consumes counted rep events and `ExerciseProgram.set.target_reps`, then reports current set progress and completion.

Keep this pure Swift and offline: no MediaPipe, no Python worker, no camera, no network, no package dependencies.

## Product / Project Value

The squat rep FSM now enforces predicate thresholds, dwell timing, ROM, and cooldown. The next layer in the M1 engine is set progress: the engine must be able to turn counted reps into a target-aware set state before form scoring, cues, replay, or UI are added.

## Scope

- Add a small `SetProgressTracker` or equivalent local type in `CamiFitEngine`.
- Initialize from `ExerciseProgram.set` or `SetConfig`.
- Consume `RepStateSnapshot` or an explicit counted-rep event and update:
  - reps completed in the current set;
  - target reps;
  - whether the set is complete on the frame/event.
- Keep behavior deterministic and independent from wall-clock time unless the existing timestamped rep event is passed through for evidence.
- Do not alter rep-counting rules except where tests need a narrow integration harness.
- Preserve current rep FSM tests and validation.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass using the default in-repo `.build`.
- Focused tests prove:
  - loading `Presets/bodyweight_squat.json` initializes target reps from `set.target_reps = 10`;
  - counted rep events advance set progress exactly once per counted frame;
  - non-counted frames do not advance set progress;
  - completion becomes true exactly when progress reaches the target and remains stable afterward.
- At least one product-path integration test feeds synthetic frames through `FrameSignalProcessor`, `RepPredicateEvaluator`, `RepStateMachine`, and the set tracker to prove one counted squat advances set progress to `1 / 10`.
- Existing `ProgramLoaderTests`, `SignalEvaluatorTests`, `FilterPipelineTests`, `RepPredicateEvaluatorTests`, and `RepStateMachineTests` remain green or are intentionally updated to the set-progress contract.

## Expected Files

- `Sources/CamiFitEngine/SetProgressTracker.swift` or a similarly named local engine file.
- `Tests/CamiFitEngineTests/SetProgressTrackerTests.swift` or focused additions to an existing test file.
- `docs/session-logs/010-executor-set-progress-tracker.md`

Names may change if the implementation finds a cleaner local structure, but keep the set-progress boundary explicit.

## Validation Commands

```bash
cd /Users/kelly/Developer/camifit
swift build --disable-sandbox
swift test --disable-sandbox
```

## Evidence To Record

- `swift build --disable-sandbox` result.
- `swift test --disable-sandbox` test count and pass/fail.
- Printed set-progress timeline showing non-counted frames ignored and counted reps advancing progress.
- Printed product-path proof showing one timed squat advances progress to `1 / 10`.

## Reachability / Demo Proof

A test must load the real `Presets/bodyweight_squat.json`, process timestamped synthetic frames through `FrameSignalProcessor`, evaluate predicates through `RepPredicateEvaluator`, feed `RepStateMachine`, and pass counted snapshots/events into the set tracker. Do not prove set progress only with hard-coded booleans.

## Out Of Scope

- Rest detection and multi-set routines.
- Hold evaluator / plank behavior.
- Form evaluator, cue scoring, replay debugger, UI, audio, Python MediaPipe worker, camera, transport, model download, Layer 2, or Layer 3.
- Golden landmark fixtures and no-person acceptance gates.

## Stop Conditions

- ESCALATE before adding any remote dependency, network access, model download, Python worker, camera code, or Layer 2/3 behavior.
- STOP if `swift test --disable-sandbox` cannot run with the default in-repo `.build`; record the exact failure.
- Do not claim coaching accuracy or milestone completion from this slice. Form rules, replay, UI, pose fixtures, and no-person/low-visibility acceptance gates are still required later.
