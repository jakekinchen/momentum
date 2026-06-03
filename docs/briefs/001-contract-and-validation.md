# Slice Brief 001 - Exercise-Program contract + load-time validation (Swift scaffold)

**Date:** 2026-06-03

## Objective

Scaffold the CamiFit Swift package and encode the **Exercise-Program contract** (per `docs/design/2026-06-03-camifit-exercise-engine-design.md` §5) as validated `Codable` models, proven by loading the bundled squat preset and **rejecting** a structurally-invalid program at load. This is the smallest useful slice: it establishes the keystone contract and the load-time validation gate that every later slice and (eventually) the agent depend on.

This slice is **pure Swift + JSON and must stay offline** — no MediaPipe, no Python worker, no network, no `pip`/SwiftPM remote dependencies.

## Product / Project Value

The Exercise-Program JSON is the single artifact both hand-authored presets and later agent-authored programs produce. Getting its shape and its load-time validation right first means every subsequent slice (DSL evaluator, filters, rep FSM, pose worker, UI) builds on a stable, tested contract, and invalid programs can never reach the live loop.

## Scope (this slice only)

- A SwiftPM package `CamiFit` with a library target `CamiFitEngine` and a test target `CamiFitEngineTests`. No app/UI target yet.
- `Codable` model types for the Exercise-Program: top-level (`schemaVersion`, `id`, `name`, `coordinate_space`), `setup`, `landmark_aliases`, `signals`, `filters`, `validity`, `rep`, `hold`, `form_rules`, `set`. Model the shapes from the design's squat and plank examples.
- A `ProgramLoader` that decodes JSON and runs **structural validation** (see Acceptance Criteria). Validation returns a precise, typed error; it never throws an opaque decode error to the caller.
- A bundled preset `Presets/bodyweight_squat.json` matching the design's squat example.
- An invalid fixture `Tests/Fixtures/invalid_missing_phase_signal.json` used to prove rejection.

## Acceptance Criteria

- `swift build` and `swift test` pass with **no remote package dependencies** (pure standard library / Foundation).
- Loading `Presets/bodyweight_squat.json` succeeds and round-trips all fields (decode → model → re-encode → key fields equal).
- Structural validation **rejects** a program when (validated at load, not at runtime):
  - `rep.phase_signal` names neither a defined signal nor a filter output;
  - a `filters[*].source` names a signal that does not exist;
  - a `form_rules[*]` / `rep` references a signal/filter name that is not defined;
  - a required field is missing or an enum value (e.g. `severity`, `coordinate_space`) is invalid.
- Each rejection yields a typed error identifying the offending field/name (asserted in tests).
- Full DSL **expression** parsing/evaluation is explicitly deferred to slice 2; this slice validates **names and structure** (string-level references), not expression grammar.

## Expected Files

- `Package.swift`
- `Sources/CamiFitEngine/ExerciseProgram.swift` (models)
- `Sources/CamiFitEngine/ProgramLoader.swift` (decode + structural validation + typed errors)
- `Presets/bodyweight_squat.json`
- `Tests/CamiFitEngineTests/ProgramLoaderTests.swift`
- `Tests/CamiFitEngineTests/Fixtures/invalid_missing_phase_signal.json`
- `docs/session-logs/001-executor-contract-and-validation.md`

## Test Plan

- Valid: squat preset loads; key fields (`id`, `rep.phase_signal`, filter names, form-rule ids) decode as expected; re-encode round-trips.
- Invalid: at least three cases — missing `rep.phase_signal` target, dangling `filters.source`, dangling form-rule signal — each asserts the specific typed error.
- Enum guard: an invalid `severity` (or `coordinate_space`) is rejected.

## Validation Commands

Record exact commands and outputs in the executor log:

```bash
cd ~/Developer/camifit            # (executor runs with -C at repo root)
swift build
swift test
```

## Evidence To Record

- `swift build` result; `swift test` count and pass/fail.
- The squat preset's decoded summary (id, signal names, filter names, rep thresholds, form-rule ids).
- The exact typed errors produced for each invalid fixture.
- Confirmation that Package.swift declares **zero remote dependencies**.

## Reachability / Demo Proof

A test (or a tiny `swift run`-able example, optional) that loads the real bundled squat preset through `ProgramLoader` and prints its validated summary — proving the contract is loadable from a real product path, not just a unit-test literal.

## Cross-Doc Impact

- None beyond writing `docs/session-logs/001-executor-contract-and-validation.md`.
- If the design's schema needs a small clarification discovered during modeling, note it in the session log for the Reviewer rather than editing the design doc directly.

## Out Of Scope (later slices)

- DSL **expression** parser/evaluator + identifier/function/DAG-cycle validation (slice 2).
- Filter runtime (EMA/median), validity gating, rep/hold/set state machines (slices 3–4).
- Python MediaPipe pose worker, `PoseProvider`, frame transport, `num_poses` (slice 5+).
- Overlay/audio/summary UI and the replay debugger.
- Any MediaPipe model download, `pip install`, or network access.

## Stop Conditions

- ESCALATE before adding any remote SwiftPM/pip dependency or downloading any model.
- STOP if `swift test` cannot run in this environment; record the blocker and the smallest next action.
- Do not implement Layer 2/3 features; if the brief seems to require them, ESCALATE.
