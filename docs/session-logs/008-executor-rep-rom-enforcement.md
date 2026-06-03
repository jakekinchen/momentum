# Executor Session 008 - Rep ROM Enforcement

Date: 2026-06-03
Role: Executor
Brief: `docs/briefs/008-rep-rom-enforcement.md`
Slice: enforce `RepConfig.min_rom_deg` in the timed rep state machine.

## Slice

Extended `RepStateMachine` so a timed rep only counts when the active attempt's configured phase signal satisfies `min_rom_deg`:

- Added `phaseSignal` input to `RepStateMachine.update`.
- Validated missing, invalid, and non-finite phase-signal values before state transitions.
- Tracked active attempt ROM with min/max values from `rep.phase_signal`.
- Added `romDegrees` to `RepStateSnapshot` for timeline evidence.
- Counted a rep only when dwell timing completes and tracked ROM is at least `rep.minROMDegrees`.
- Reset ROM tracking after a counted or aborted attempt.
- Preserved no-false-rep and invalid-frame behavior from prior slices.

## Files Changed

- `Sources/CamiFitEngine/RepStateMachine.swift`
- `Tests/CamiFitEngineTests/RepStateMachineTests.swift`
- `docs/session-logs/008-executor-rep-rom-enforcement.md`

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

RepStateMachineTests.swift:17:52: error: value of type 'RepStateSnapshot' has no member 'romDegrees'
RepStateMachineTests.swift:158:38: error: extra argument 'phaseSignal' in call
```

Focused validation:

```text
swift test --disable-sandbox --filter RepStateMachineTests

Test Suite 'RepStateMachineTests' passed
Executed 7 tests, with 0 failures (0 unexpected)
rep-state-timed-one-rep ... 16:ready:reps=1:counted=true:rom=82.1 ...
rep-state-below-rom ... 16:ready:reps=0:counted=false:rom=82.1 ...
rep-state-invalid phase=ready reps=0 counted=false invalid=phase signal knee invalid: filter knee source knee_raw invalid: low confidence landmark primary.knee visibility=0.2 presence=1.0 threshold=0.65
```

Broad validation:

```text
swift build --disable-sandbox

Build complete! (0.15s)
```

```text
swift test --disable-sandbox

Test Suite 'All tests' passed
Executed 29 tests, with 0 failures (0 unexpected)
rep-state-timed-one-rep ... 16:ready:reps=1:counted=true:rom=82.1 ...
rep-state-below-rom ... 16:ready:reps=0:counted=false:rom=82.1 ...
rep-state-invalid phase=ready reps=0 counted=false invalid=phase signal knee invalid: filter knee source knee_raw invalid: low confidence landmark primary.knee visibility=0.2 presence=1.0 threshold=0.65
```

## Reachability Evidence

`RepStateMachineTests.ProductPathHarness` loads the real preset, processes frames, evaluates predicates, reads the configured phase signal, and feeds all of it into the state machine:

```swift
let program = try ProgramLoader.load(from: RepStateMachineTests.presetURL)
let rep = try XCTUnwrap(program.rep)
processor = try FrameSignalProcessor(program: program)
predicateEvaluator = try RepPredicateEvaluator(program: program)
stateMachine = RepStateMachine(rep: stateMachineRep)
phaseSignalName = stateMachineRep.phaseSignal
let produced = processor.process(frame: frame)
let down = predicateEvaluator.evaluateDown(producedValues: produced, frame: frame)
let up = predicateEvaluator.evaluateUp(producedValues: produced, frame: frame)
return stateMachine.update(
    timestampMS: frame.timestampMS,
    phaseSignal: produced[phaseSignalName],
    downPredicate: down,
    upPredicate: up
)
```

The real preset valid path counts one timed rep with observed ROM above the configured `50` degree threshold:

```text
rep-state-timed-one-rep ... 14:ascending:reps=0:counted=false:rom=72.9 15:ascending:reps=0:counted=false:rom=78.5 16:ready:reps=1:counted=true:rom=82.1
```

The below-ROM test uses the same loaded preset product path and a state-machine `RepConfig` variant with `minROMDegrees` raised to `100`, because the real squat preset's `knee < 100` and `knee > 160` predicates inherently imply more than the preset's `50` degree ROM. That enforcement path does not count:

```text
rep-state-below-rom ... 14:ascending:reps=0:counted=false:rom=72.9 15:ascending:reps=0:counted=false:rom=78.5 16:ready:reps=0:counted=false:rom=82.1
```

## Flags For Reviewer

- This slice intentionally does not enforce `cooldown_ms`.
- This slice does not implement set tracking, rest detection, hold evaluator, form rules, cue scoring, replay debugger, UI, audio, Python, MediaPipe, camera, network, Layer 2, or Layer 3.
- The no-count below-ROM proof uses a high-ROM state-machine config derived from the loaded preset; with the real preset thresholds and `min_rom_deg = 50`, any successful down/up threshold crossing already exceeds minimum ROM.
- Invalid phase-signal frames reset active dwell timing and do not update active ROM tracking.

## Next Suggested Slice

Add `cooldown_ms` enforcement after counted reps so a completed rep cannot double-count during repeated up frames, while keeping set tracking and form rules deferred.
