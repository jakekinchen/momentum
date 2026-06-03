# Executor Session 002 - Calibration Signal-Reference Validation

Date: 2026-06-03
Role: Executor
Brief: `docs/briefs/002-dsl-evaluator-and-calibration-validation.md`
Slice: smallest useful sub-slice from the active brief: load-time validation for `setup.calibration.*.signals`.

## Slice

Closed the carried-forward Reviewer gap from session 001:

- Added typed `ProgramLoadError.invalidCalibrationSignalReference(field:name:)`.
- Validates every `setup.calibration.<capture>.signals[]` entry against the values produced by `signals` and `filters`.
- Added an invalid fixture for an unknown calibration signal.
- Extended the real squat preset loader test to assert and print valid calibration references.
- Declared test `Fixtures` as test resources so SwiftPM no longer warns about unhandled JSON fixtures.

The runtime DSL parser/evaluator requested by the broader brief is not implemented in this sub-slice.

## Files Changed

- `Package.swift`
- `Sources/CamiFitEngine/ProgramLoader.swift`
- `Tests/CamiFitEngineTests/ProgramLoaderTests.swift`
- `Tests/CamiFitEngineTests/Fixtures/invalid_calibration_signal_ref.json`
- `docs/session-logs/002-executor-dsl-evaluator-and-calibration-validation.md`

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
swift test --disable-sandbox --filter ProgramLoaderTests

ProgramLoaderTests.swift:98:29: error: type '_ErrorCodeProtocol' has no member 'invalidCalibrationSignalReference'
```

Focused validation:

```text
swift test --disable-sandbox --filter ProgramLoaderTests

Test Suite 'ProgramLoaderTests' passed
Executed 9 tests, with 0 failures (0 unexpected)
validated-summary id=bodyweight_squat signals=knee_left,knee_raw,knee_right,knee_symmetry,torso_raw filters=knee,torso_tilt rep_phase=knee,down=knee < 100,up=knee > 160 hold_signal=nil form_rules=depth,torso,symmetry
validated-calibration top_pose signals=["knee", "torso_tilt"]
calibration-error invalid_calibration_signal_reference(field: setup.calibration.top_pose.signals[0], name: missing_calibration_signal)
```

Broad validation:

```text
swift build --disable-sandbox

Build complete! (0.11s)
```

```text
swift test --disable-sandbox

Test Suite 'All tests' passed
Executed 9 tests, with 0 failures (0 unexpected)
validated-calibration top_pose signals=["knee", "torso_tilt"]
calibration-error invalid_calibration_signal_reference(field: setup.calibration.top_pose.signals[0], name: missing_calibration_signal)
```

## Reachability Evidence

The real product preset path `Presets/bodyweight_squat.json` is loaded by `ProgramLoader` in `testBundledSquatPresetLoadsAndRoundTripsFromProductPath`.

Evidence from the focused and broad test runs:

```text
validated-calibration top_pose signals=["knee", "torso_tilt"]
```

The invalid fixture `Tests/CamiFitEngineTests/Fixtures/invalid_calibration_signal_ref.json` is rejected at load with the typed error:

```text
calibration-error invalid_calibration_signal_reference(field: setup.calibration.top_pose.signals[0], name: missing_calibration_signal)
```

## Flags For Reviewer

- This is an intentionally narrow sub-slice from brief 002. It does not implement `PoseFrame`, parser/AST, `SignalValue`, or runtime expression evaluation.
- SwiftPM validation now works with the Manager-approved convention: default in-repo `.build` plus `--disable-sandbox`; no external scratch/cache paths were used.
- No network, model download, remote dependency, Python, MediaPipe, Layer 2, or Layer 3 work was added.

## Next Suggested Slice

Implement the first runtime evaluator increment: `PoseFrame`, `SignalValue`, landmark lookup, and numeric/function evaluation for the squat preset's arithmetic functions (`angle`, `angle_to_vertical`, `abs`) before broadening to comparisons, boolean operators, membership, and holds.
