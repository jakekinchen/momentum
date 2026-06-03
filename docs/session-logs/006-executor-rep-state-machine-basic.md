# Executor Session 006 - Basic Rep State Machine

Date: 2026-06-03
Role: Executor
Brief: `docs/briefs/006-rep-state-machine-basic.md`
Slice: minimal squat rep state machine over produced values and predicate results.

## Slice

Implemented the first deterministic rep state-machine increment:

- Added `RepStateMachine`, initialized from `ExerciseProgram.rep`.
- Added `RepPhase` with `seeking_ready`, `ready`, and `down`.
- Added `RepStateSnapshot` exposing current phase, rep count, whether the current frame counted, and optional invalid reason.
- Implemented the minimal transition path:
  - `up_when == true` establishes `ready`;
  - `down_when == true` from `ready` enters `down`;
  - `up_when == true` from `down` counts one rep and returns to `ready`.
- Invalid predicate frames do not transition or count, and preserve an explicit invalid reason.
- Added product-path tests that load `Presets/bodyweight_squat.json`, process synthetic frames through `FrameSignalProcessor`, evaluate predicates through `RepPredicateEvaluator`, and feed results into the state machine.

## Files Changed

- `Sources/CamiFitEngine/RepStateMachine.swift`
- `Tests/CamiFitEngineTests/RepStateMachineTests.swift`
- `docs/session-logs/006-executor-rep-state-machine-basic.md`

## Validation

Startup audit:

```text
git status --short --branch --untracked-files=all
## main

scripts/audit_autonomous_workflow.sh
workflow audit clean
```

Test-first red run:

```text
swift test --disable-sandbox --filter RepStateMachineTests

RepStateMachineTests.swift:71:27: error: cannot find type 'RepStateMachine' in scope
RepStateMachineTests.swift:80:52: error: cannot find type 'RepStateSnapshot' in scope
```

Focused validation:

```text
swift test --disable-sandbox --filter RepStateMachineTests

Test Suite 'RepStateMachineTests' passed
Executed 4 tests, with 0 failures (0 unexpected)
rep-state-one-rep 0:ready:reps=0:counted=false 1:ready:reps=0:counted=false 2:ready:reps=0:counted=false 3:ready:reps=0:counted=false 4:ready:reps=0:counted=false 5:ready:reps=0:counted=false 6:down:reps=0:counted=false 7:down:reps=0:counted=false 8:down:reps=0:counted=false 9:down:reps=0:counted=false 10:ready:reps=1:counted=true 11:ready:reps=1:counted=false
rep-state-no-false standing=0:ready:reps=0:counted=false 1:ready:reps=0:counted=false 2:ready:reps=0:counted=false 3:ready:reps=0:counted=false 4:ready:reps=0:counted=false 5:ready:reps=0:counted=false shallow=0:ready:reps=0:counted=false 1:ready:reps=0:counted=false 2:ready:reps=0:counted=false 3:ready:reps=0:counted=false 4:ready:reps=0:counted=false 5:ready:reps=0:counted=false 6:ready:reps=0:counted=false 7:ready:reps=0:counted=false 8:ready:reps=0:counted=false 9:ready:reps=0:counted=false 10:ready:reps=0:counted=false 11:ready:reps=0:counted=false
rep-state-deep-start 0:seeking_ready:reps=0:counted=false 1:seeking_ready:reps=0:counted=false 2:seeking_ready:reps=0:counted=false 3:seeking_ready:reps=0:counted=false 4:seeking_ready:reps=0:counted=false 5:seeking_ready:reps=0:counted=false 6:seeking_ready:reps=0:counted=false 7:seeking_ready:reps=0:counted=false 8:seeking_ready:reps=0:counted=false 9:ready:reps=0:counted=false 10:ready:reps=0:counted=false
rep-state-invalid phase=ready reps=0 counted=false invalid=down predicate invalid: signal knee invalid: filter knee source knee_raw invalid: low confidence landmark primary.knee visibility=0.2 presence=1.0 threshold=0.65
```

Broad validation:

```text
swift build --disable-sandbox

Build complete! (0.14s)
```

```text
swift test --disable-sandbox

Test Suite 'All tests' passed
Executed 26 tests, with 0 failures (0 unexpected)
rep-state-one-rep 0:ready:reps=0:counted=false 1:ready:reps=0:counted=false 2:ready:reps=0:counted=false 3:ready:reps=0:counted=false 4:ready:reps=0:counted=false 5:ready:reps=0:counted=false 6:down:reps=0:counted=false 7:down:reps=0:counted=false 8:down:reps=0:counted=false 9:down:reps=0:counted=false 10:ready:reps=1:counted=true 11:ready:reps=1:counted=false
rep-state-invalid phase=ready reps=0 counted=false invalid=down predicate invalid: signal knee invalid: filter knee source knee_raw invalid: low confidence landmark primary.knee visibility=0.2 presence=1.0 threshold=0.65
```

## Reachability Evidence

`RepStateMachineTests.ProductPathHarness` uses the real product path for every state-machine step:

```swift
let program = try ProgramLoader.load(from: RepStateMachineTests.presetURL)
processor = try FrameSignalProcessor(program: program)
predicateEvaluator = try RepPredicateEvaluator(program: program)
stateMachine = try RepStateMachine(program: program)
let produced = processor.process(frame: frame)
let down = predicateEvaluator.evaluateDown(producedValues: produced, frame: frame)
let up = predicateEvaluator.evaluateUp(producedValues: produced, frame: frame)
return stateMachine.update(downPredicate: down, upPredicate: up)
```

The product-path one-rep timeline proves that filtered signals and predicates can drive one deterministic squat count:

```text
rep-state-one-rep 0:ready:reps=0:counted=false 1:ready:reps=0:counted=false 2:ready:reps=0:counted=false 3:ready:reps=0:counted=false 4:ready:reps=0:counted=false 5:ready:reps=0:counted=false 6:down:reps=0:counted=false 7:down:reps=0:counted=false 8:down:reps=0:counted=false 9:down:reps=0:counted=false 10:ready:reps=1:counted=true 11:ready:reps=1:counted=false
```

The no-false-rep and invalid-frame evidence are also recorded in focused and broad validation output.

## Flags For Reviewer

- This slice intentionally does not enforce `down_min_ms`, `bottom_min_ms`, `up_min_ms`, `cooldown_ms`, or `min_rom_deg`.
- This slice does not implement set tracking, hold evaluator, form rules, validity freeze/reset timing, UI, audio, Python, MediaPipe, camera, network, Layer 2, or Layer 3.
- The state machine starts in `seeking_ready`; deep/down frames before an initial up/ready frame cannot count a rep.
- The squat preset's EMA filter means the test uses repeated deep/up posture frames so the real filtered `knee` signal crosses configured thresholds.

## Next Suggested Slice

Add minimal dwell-timing enforcement for `down_min_ms`, `bottom_min_ms`, and `up_min_ms` using `PoseFrame.timestampMS` or equivalent timestamps in the state-machine update path, while keeping ROM/cooldown/set tracking deferred.
