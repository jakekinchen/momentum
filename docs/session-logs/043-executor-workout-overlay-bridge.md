# Session Log 043 - Workout Overlay Bridge

## Summary

Connected the member overlay workspace to the Swift workout generator so app
startup paths can generate workouts from the current merged KG view without
manually threading member constraints.

## Implementation

- Added `WorkoutGenerator.generateWorkout(view:prompt:minutes:availableEquipment:)`
  to derive the `SafetyEngine` from `MergedGraphView` and pass
  `activeResolvedConstraints` into the existing deterministic generator.
- Added `WorkoutGenerator.generateWorkout(workspace:prompt:minutes:availableEquipment:)`
  as a convenience for Application Support workspace callers.
- Added a bridge test that appends a left-knee medical constraint, verifies a
  lower-body workout excludes `Exercise:goblet_squat`, then appends a user
  correction and verifies the generator selects the squat again.

## Validation Evidence

```text
swift test --disable-sandbox --filter KGKitTests
Result: passed, 56 tests.

./scripts/run_monorepo_gates.sh
Result: passed.
- kg-python: 152 passed
- kg-validation: validation_status pass, verified false
- assessment-import: pass, exact golden counts 50/19/9/36/32
- artifact-build: regenerated safety, resolve, alternatives, and workout vectors
- conformance-parity: safety/resolve/alternatives/workout tests passed
- swift-test: 182 passed
- contracts-compat: graph-operation and decision-explanation schemas detected
```

## Result

The core path now demonstrates the intended user-correction loop: a durable KG
overlay can exclude an exercise for an active restriction, and a later user
retraction removes that restriction from subsequent deterministic workout
generation.
