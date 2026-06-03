# Executor Session 007 - Rep State-Machine Dwell Timing

Date: 2026-06-03
Role: Executor
Brief: `docs/briefs/007-rep-state-machine-dwell-timing.md`
Slice: timestamped dwell timing for squat rep transitions.

## Slice

Extended the basic rep state machine to enforce the configured dwell timings from `RepConfig`:

- Added timestamp input to `RepStateMachine.update`.
- Expanded phases from basic `down` to `descending`, `bottom`, and `ascending`.
- Enforced `down_min_ms` before accepting the bottom phase.
- Enforced `bottom_min_ms` before allowing the up transition.
- Enforced `up_min_ms` before counting a rep.
- Preserved repeated-standing, shallow-movement, and deep-before-ready no-false-rep behavior.
- Reset active dwell timers on invalid predicate frames so invalid time cannot satisfy dwell requirements.

## Files Changed

- `Sources/CamiFitEngine/RepStateMachine.swift`
- `Tests/CamiFitEngineTests/RepStateMachineTests.swift`
- `docs/session-logs/007-executor-rep-state-machine-dwell-timing.md`

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

RepStateMachineTests.swift:98:40: error: type 'RepPhase' has no member 'descending'
RepStateMachineTests.swift:123:59: error: extra argument 'timestampMS' in call
```

Focused validation:

```text
swift test --disable-sandbox --filter RepStateMachineTests

Test Suite 'RepStateMachineTests' passed
Executed 6 tests, with 0 failures (0 unexpected)
rep-state-timed-one-rep 0:ready:reps=0:counted=false 1:ready:reps=0:counted=false 2:ready:reps=0:counted=false 3:ready:reps=0:counted=false 4:ready:reps=0:counted=false 5:ready:reps=0:counted=false 6:descending:reps=0:counted=false 7:descending:reps=0:counted=false 8:bottom:reps=0:counted=false 9:bottom:reps=0:counted=false 10:bottom:reps=0:counted=false 11:bottom:reps=0:counted=false 12:bottom:reps=0:counted=false 13:bottom:reps=0:counted=false 14:ascending:reps=0:counted=false 15:ascending:reps=0:counted=false 16:ready:reps=1:counted=true 17:ready:reps=1:counted=false 18:ready:reps=1:counted=false
rep-state-too-fast 0:ready:reps=0:counted=false 1:ready:reps=0:counted=false 2:ready:reps=0:counted=false 3:ready:reps=0:counted=false 4:ready:reps=0:counted=false 5:ready:reps=0:counted=false 6:descending:reps=0:counted=false 7:descending:reps=0:counted=false 8:descending:reps=0:counted=false 9:descending:reps=0:counted=false 10:descending:reps=0:counted=false 11:ready:reps=0:counted=false ...
rep-state-invalid-dwell 0:ready:reps=0:counted=false 1:ready:reps=0:counted=false 2:ready:reps=0:counted=false 3:ready:reps=0:counted=false 4:ready:reps=0:counted=false 5:ready:reps=0:counted=false 6:descending:reps=0:counted=false 7:descending:reps=0:counted=false 8:descending:reps=0:counted=false invalid=phase=descending reps=0 counted=false invalid=down predicate invalid: signal knee invalid: filter knee source knee_raw invalid: low confidence landmark primary.knee visibility=0.2 presence=1.0 threshold=0.65
```

Broad validation:

```text
swift build --disable-sandbox

Build complete! (0.14s)
```

```text
swift test --disable-sandbox

Test Suite 'All tests' passed
Executed 28 tests, with 0 failures (0 unexpected)
rep-state-timed-one-rep 0:ready:reps=0:counted=false 1:ready:reps=0:counted=false 2:ready:reps=0:counted=false 3:ready:reps=0:counted=false 4:ready:reps=0:counted=false 5:ready:reps=0:counted=false 6:descending:reps=0:counted=false 7:descending:reps=0:counted=false 8:bottom:reps=0:counted=false 9:bottom:reps=0:counted=false 10:bottom:reps=0:counted=false 11:bottom:reps=0:counted=false 12:bottom:reps=0:counted=false 13:bottom:reps=0:counted=false 14:ascending:reps=0:counted=false 15:ascending:reps=0:counted=false 16:ready:reps=1:counted=true 17:ready:reps=1:counted=false 18:ready:reps=1:counted=false
rep-state-too-fast 0:ready:reps=0:counted=false 1:ready:reps=0:counted=false 2:ready:reps=0:counted=false 3:ready:reps=0:counted=false 4:ready:reps=0:counted=false 5:ready:reps=0:counted=false 6:descending:reps=0:counted=false 7:descending:reps=0:counted=false 8:descending:reps=0:counted=false 9:descending:reps=0:counted=false 10:descending:reps=0:counted=false 11:ready:reps=0:counted=false ...
rep-state-invalid-dwell 0:ready:reps=0:counted=false 1:ready:reps=0:counted=false 2:ready:reps=0:counted=false 3:ready:reps=0:counted=false 4:ready:reps=0:counted=false 5:ready:reps=0:counted=false 6:descending:reps=0:counted=false 7:descending:reps=0:counted=false 8:descending:reps=0:counted=false invalid=phase=descending reps=0 counted=false invalid=down predicate invalid: signal knee invalid: filter knee source knee_raw invalid: low confidence landmark primary.knee visibility=0.2 presence=1.0 threshold=0.65
```

## Reachability Evidence

`RepStateMachineTests.ProductPathHarness` still drives every update through the real product path:

```swift
let program = try ProgramLoader.load(from: RepStateMachineTests.presetURL)
processor = try FrameSignalProcessor(program: program)
predicateEvaluator = try RepPredicateEvaluator(program: program)
stateMachine = try RepStateMachine(program: program)
let produced = processor.process(frame: frame)
let down = predicateEvaluator.evaluateDown(producedValues: produced, frame: frame)
let up = predicateEvaluator.evaluateUp(producedValues: produced, frame: frame)
return stateMachine.update(timestampMS: frame.timestampMS, downPredicate: down, upPredicate: up)
```

The valid timed sequence loads `Presets/bodyweight_squat.json`, uses timestamped synthetic frames, and counts exactly one rep only after `descending -> bottom -> ascending` dwell completion:

```text
rep-state-timed-one-rep 0:ready:reps=0:counted=false ... 8:bottom:reps=0:counted=false ... 14:ascending:reps=0:counted=false 15:ascending:reps=0:counted=false 16:ready:reps=1:counted=true
```

The too-fast sequence and invalid-frame dwell reset are recorded in the focused and broad validation evidence above.

## Flags For Reviewer

- This slice intentionally does not enforce `min_rom_deg` or `cooldown_ms`.
- This slice does not implement set tracking, hold evaluator, form rules, cue scoring, replay/debugger, UI, audio, Python, MediaPipe, camera, network, Layer 2, or Layer 3.
- Invalid predicate frames preserve the visible phase but reset the active dwell timer; this is intentionally conservative and avoids counting through invalid time.
- If an up transition occurs before `bottom_min_ms`, this implementation resets to `ready` without counting.

## Next Suggested Slice

Add `min_rom_deg` enforcement using the configured `rep.phase_signal` value across a rep attempt, while keeping cooldown and set tracking deferred.
