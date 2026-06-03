# Executor Session 001 - Contract and Validation

Date: 2026-06-03
Role: Executor
Brief: `docs/briefs/001-contract-and-validation.md`
Decision state: implemented slice with a validation-environment blocker for SwiftPM test execution.

## Slice

Scaffolded the pure Swift/JSON Layer 1 contract gate:

- SwiftPM package `CamiFit` with library target `CamiFitEngine` and test target `CamiFitEngineTests`.
- `Codable` Exercise-Program models for setup, aliases, signals, filters, validity, rep/hold, form rules, and set target.
- `ProgramLoader` that maps decode failures to typed `ProgramLoadError` values and runs load-time structural validation.
- Bundled squat preset at `Presets/bodyweight_squat.json`.
- Invalid missing-field fixture at `Tests/CamiFitEngineTests/Fixtures/invalid_missing_phase_signal.json`.
- XCTest coverage for valid preset loading/round-trip and typed rejection cases.

## Files Changed

- `Package.swift`
- `Sources/CamiFitEngine/ExerciseProgram.swift`
- `Sources/CamiFitEngine/ProgramLoader.swift`
- `Presets/bodyweight_squat.json`
- `Tests/CamiFitEngineTests/ProgramLoaderTests.swift`
- `Tests/CamiFitEngineTests/Fixtures/invalid_missing_phase_signal.json`
- `docs/session-logs/001-executor-contract-and-validation.md`

## Validation

Startup audit:

```text
git status --short --branch
## main

scripts/audit_autonomous_workflow.sh
workflow audit clean
```

SwiftPM graph/dependency proof:

```text
swift package --disable-sandbox --scratch-path /private/tmp/camifit-swiftpm-describe2 --cache-path /private/tmp/camifit-swiftpm-cache-desc2 --config-path /private/tmp/camifit-swiftpm-config-desc2 --security-path /private/tmp/camifit-swiftpm-security-desc2 describe

Dependencies:

Products:
  CamiFitEngine

Targets:
  CamiFitEngineTests -> CamiFitEngine
  CamiFitEngine
```

This confirms `Package.swift` declares zero remote package dependencies.

Focused SwiftPM test command from the brief is blocked before compilation:

```text
swift test --filter ProgramLoaderTests
sandbox-exec: sandbox_apply: Operation not permitted
```

Retry with SwiftPM sandbox disabled is also blocked before compilation:

```text
swift test --disable-sandbox --scratch-path /private/tmp/camifit-swiftpm-build6 --cache-path /private/tmp/camifit-swiftpm-cache6 --config-path /private/tmp/camifit-swiftpm-config6 --security-path /private/tmp/camifit-swiftpm-security6 --filter ProgramLoaderTests
error: encountered an I/O error (code: 1) while reading /private/tmp/camifit-swiftpm-build6/arm64-apple-macosx/debug/CamiFitEngine.build/output-file-map.json
```

Broad SwiftPM build command is blocked the same way:

```text
swift build --disable-sandbox --manifest-cache none --disable-build-manifest-caching --disable-dependency-cache --disable-index-store --scratch-path /private/tmp/camifit-swiftpm-build7 --cache-path /private/tmp/camifit-swiftpm-cache7 --config-path /private/tmp/camifit-swiftpm-config7 --security-path /private/tmp/camifit-swiftpm-security7
error: encountered an I/O error (code: 1) while reading /private/tmp/camifit-swiftpm-build7/arm64-apple-macosx/debug/CamiFitEngine.build/output-file-map.json
```

Xcode/SwiftBuild backends also fail before compilation due write restrictions:

```text
swift test --build-system xcode ...
unable to write manifest to '/private/tmp/camifit-swiftpm-build-xcode/apple/Intermediates.noindex/XCBuildData/.../manifest.json': Operation not permitted
```

Direct compiler validation:

```text
swiftc -typecheck Sources/CamiFitEngine/ExerciseProgram.swift Sources/CamiFitEngine/ProgramLoader.swift
# pass

swiftc -emit-library -emit-module -enable-testing -module-name CamiFitEngine Sources/CamiFitEngine/ExerciseProgram.swift Sources/CamiFitEngine/ProgramLoader.swift -emit-module-path /private/tmp/CamiFitEngine.swiftmodule -o /private/tmp/libCamiFitEngine.dylib
# pass
```

## Reachability Evidence

Real product path load through `ProgramLoader`:

```text
DYLD_LIBRARY_PATH=/private/tmp swift -I /private/tmp -L /private/tmp -lCamiFitEngine -e '... ProgramLoader.load(from: URL(fileURLWithPath: "Presets/bodyweight_squat.json")) ...'

validated-summary id=bodyweight_squat signals=knee_left,knee_raw,knee_right,knee_symmetry,torso_raw filters=knee,torso_tilt rep_phase=knee,down=knee < 100,up=knee > 160 hold_signal=nil form_rules=depth,torso,symmetry
```

Typed rejection evidence:

```text
missing_required_field(field: rep.phase_signal)
missing_reference(field: rep.phase_signal, name: missing_phase)
missing_reference(field: filters.knee.source, name: missing_raw_signal)
missing_reference(field: form_rules[0].expect, name: missing_depth)
invalid_enum_value(field: form_rules[0].severity, value: urgent, allowed: fail,info,warn)
unknown_function(field: signals.knee_raw, name: mystery_angle, allowed: abs,angle,angle_to_horizontal,angle_to_vertical,distance,max,midpoint,min,ratio,signed_angle)
cyclic_signal_reference(name: cycle_a)
```

## Flags For Reviewer

- Stop-condition note: `swift test` cannot run in this environment. The command fails before compiling package sources due SwiftPM/Xcode sandbox or write restrictions. Direct `swiftc` library compile and fileless loader checks pass.
- The brief says full DSL expression parsing/evaluation is slice 2. This slice only token-scans expressions for names/functions and detects signal cycles so invalid programs cannot pass the load-time gate required by `GOAL.md`.
- `setup.calibration.*.signals` is decoded but not yet validated against produced signals because calibration capture semantics are not executable in this slice. Reviewer should decide whether to add that to slice 2 validation.

## Next Suggested Slice

Smallest next action is environment-facing: run `swift test --filter ProgramLoaderTests` outside this restricted runner or repair the SwiftPM/Xcode write-path issue so the committed XCTest suite can execute normally. After that is green, proceed to slice 2: real DSL parser/AST validation without runtime evaluation.
