# Executor Session 004 - Filter Pipeline + Produced Values

Date: 2026-06-03
Role: Executor
Brief: `docs/briefs/004-filter-pipeline-produced-values.md`
Slice: stateful filter runtime plus raw/filtered produced-value table.

## Slice

Implemented the filter runtime needed to connect raw squat signals to the contract names used by later rep/form logic:

- Added `FilterPipeline`, initialized from an `ExerciseProgram`.
- Added EMA support using configured `alpha`.
- Added median support using `window_ms` and `PoseFrame.timestampMS`.
- Added invalid-source behavior: invalid raw source values produce invalid filtered outputs and do not update numeric filter state.
- Added confidence propagation:
  - EMA confidence follows the same alpha as the value.
  - Median confidence is the selected median sample confidence; for even-count median, it is the lower confidence of the two middle samples.
- Added `FrameSignalProcessor` to evaluate raw signals and merge filtered outputs into one produced-value table.
- Added tests for EMA, median windowing, invalid source recovery, determinism, and the real squat preset produced table.

## Files Changed

- `Sources/CamiFitEngine/FilterPipeline.swift`
- `Sources/CamiFitEngine/FrameSignalProcessor.swift`
- `Tests/CamiFitEngineTests/FilterPipelineTests.swift`
- `docs/session-logs/004-executor-filter-pipeline-produced-values.md`

## Validation

Startup audit:

```text
git status --short --branch
## main

scripts/audit_autonomous_workflow.sh
workflow audit clean
```

Test-first red run:

```text
swift test --disable-sandbox --filter FilterPipelineTests

FilterPipelineTests.swift:6:24: error: cannot find 'FilterPipeline' in scope
FilterPipelineTests.swift:71:29: error: cannot find 'FrameSignalProcessor' in scope
```

Focused validation:

```text
swift test --disable-sandbox --filter FilterPipelineTests

Test Suite 'FilterPipelineTests' passed
Executed 5 tests, with 0 failures (0 unexpected)
ema-sequence valid(1.000, confidence: 1.000),valid(2.000, confidence: 0.750),valid(3.500, confidence: 0.875)
invalid-source-output invalid(filter smooth source raw invalid: low confidence landmark left.knee) recovered=valid(15.000, confidence: 1.000)
median-window even_policy=average-middle valid(1.000, confidence: 0.800),valid(3.000, confidence: 0.600),valid(3.000, confidence: 1.000),valid(6.000, confidence: 1.000)
produced-squat-table knee=valid(180.000, confidence: 1.000) knee_left=valid(180.000, confidence: 1.000) knee_raw=valid(180.000, confidence: 1.000) knee_right=valid(180.000, confidence: 1.000) knee_symmetry=valid(0.000, confidence: 1.000) torso_raw=valid(0.000, confidence: 1.000) torso_tilt=valid(0.000, confidence: 1.000)
```

Broad validation:

```text
swift build --disable-sandbox

Build complete! (0.14s)
```

```text
swift test --disable-sandbox

Test Suite 'All tests' passed
Executed 18 tests, with 0 failures (0 unexpected)
ema-sequence valid(1.000, confidence: 1.000),valid(2.000, confidence: 0.750),valid(3.500, confidence: 0.875)
invalid-source-output invalid(filter smooth source raw invalid: low confidence landmark left.knee) recovered=valid(15.000, confidence: 1.000)
median-window even_policy=average-middle valid(1.000, confidence: 0.800),valid(3.000, confidence: 0.600),valid(3.000, confidence: 1.000),valid(6.000, confidence: 1.000)
produced-squat-table knee=valid(180.000, confidence: 1.000) knee_left=valid(180.000, confidence: 1.000) knee_raw=valid(180.000, confidence: 1.000) knee_right=valid(180.000, confidence: 1.000) knee_symmetry=valid(0.000, confidence: 1.000) torso_raw=valid(0.000, confidence: 1.000) torso_tilt=valid(0.000, confidence: 1.000)
```

## Reachability Evidence

`FilterPipelineTests.testSquatPresetProducedValueTableContainsRawAndFilteredValues` loads the real product preset and runs the new integrated path:

```swift
let program = try ProgramLoader.load(from: presetURL)
var processor = try FrameSignalProcessor(program: program)
let produced = processor.process(frame: standingFrame)
```

The printed produced table includes both raw names and filtered names:

```text
produced-squat-table knee=valid(180.000, confidence: 1.000) knee_left=valid(180.000, confidence: 1.000) knee_raw=valid(180.000, confidence: 1.000) knee_right=valid(180.000, confidence: 1.000) knee_symmetry=valid(0.000, confidence: 1.000) torso_raw=valid(0.000, confidence: 1.000) torso_tilt=valid(0.000, confidence: 1.000)
```

## Flags For Reviewer

- Filters intentionally read from the raw signal table only. Filter-to-filter dependencies remain out of scope.
- Invalid source input returns an invalid filtered value for that frame and does not update the numeric filter state.
- Median even-count policy is average of the two middle values.
- This slice does not evaluate predicates, rep/hold/set state machines, validity timing policy, form rules, UI, Python, MediaPipe, camera, network, Layer 2, or Layer 3.

## Next Suggested Slice

Add predicate/comparison expression evaluation for `rep.down_when` and `rep.up_when` over the produced-value table (`knee`, `torso_tilt`, etc.) as the next step toward the rep state machine.
