# Slice Brief 023 - Lunge Preset (M2)

**Date:** 2026-06-03

## Objective

Add a **lunge** Exercise-Program as data + golden acceptance fixtures, proving the existing data-driven contract handles a third exercise with no new engine architecture.

Pure Swift + JSON, offline. Do not modify `Sources/CamiFitEngine/`, `pose_worker/`, the macOS app, network code, or downloads.

## Product / Project Value

Lunge is the second M2 preset after push-up. It should further prove that new bodyweight exercises can be added by authoring an Exercise-Program and fixtures rather than changing the engine.

## Scope

- Add `Presets/bodyweight_lunge.json` using the existing Exercise-Program contract.
- Use a side-view single-leg lunge model with existing supported DSL functions only.
- Suggested signal shape:
  - front knee angle: `angle(front.hip, front.knee, front.ankle)` or the equivalent mapped `primary.*` names if the fixture uses `primary` as the front leg;
  - optional rear knee or hip/torso signal if useful for form evidence;
  - a symmetry / torso / knee-tracking form signal only if expressible with current DSL functions.
- Suggested rep shape:
  - `down_when` around front knee bend, e.g. knee angle below an explicit threshold;
  - `up_when` at standing/top knee angle;
  - ROM, dwell timing, and cooldown similar in spirit to squat/push-up, but tuned to the synthetic lunge fixture.
- Add at least one form rule, preferably depth or torso posture, using existing `form_rules` semantics.
- Add small checked-in synthetic fixtures under `Tests/CamiFitEngineTests/Fixtures/`:
  - `synthetic_lunge_clean_trace.json` — at least one full lunge rep that should count exactly.
  - `synthetic_lunge_shallow_trace.json` — partial/shallow lunge that must not count.
- Add `Tests/CamiFitEngineTests/LungeAcceptanceTests.swift`:
  - load `bodyweight_lunge.json` through `ProgramLoader`;
  - load fixtures through `PoseFrameFixtureLoader`;
  - run `EngineTraceRecorder` and `EngineTraceFormatter`;
  - assert clean exact final rep count and counted timestamp(s) within explicit tolerance;
  - assert shallow exact final rep count `0`;
  - print acceptance evidence mirroring the push-up/squat acceptance style.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass using the default in-repo `.build`.
- `bodyweight_lunge.json` loads and validates through `ProgramLoader`.
- Clean fixture asserts exact final rep count and counted timestamp(s) within an explicit tolerance.
- Shallow fixture asserts exact final rep count `0`.
- Existing squat and push-up acceptance tests remain green.
- No new files under `Sources/CamiFitEngine/`.
- No changes under `pose_worker/`.
- No model download, camera access, SwiftUI app run, network dependency, Layer 2, or Layer 3 behavior is added.

## Expected Files

- `Presets/bodyweight_lunge.json`
- `Tests/CamiFitEngineTests/Fixtures/synthetic_lunge_clean_trace.json`
- `Tests/CamiFitEngineTests/Fixtures/synthetic_lunge_shallow_trace.json`
- `Tests/CamiFitEngineTests/LungeAcceptanceTests.swift`
- `docs/session-logs/023-executor-lunge-preset.md`

## Validation Commands

```bash
cd /Users/kelly/Developer/camifit
swift build --disable-sandbox
swift test --disable-sandbox
```

Do not run or block on pytest unless this slice unexpectedly modifies `pose_worker/`, in which case ESCALATE for a manager pytest run.

## Evidence To Record

- `swift build --disable-sandbox` result.
- `swift test --disable-sandbox` test count and pass/fail.
- Focused lunge acceptance result.
- Acceptance summary for each case:
  - fixture name;
  - frame count;
  - expected rep count;
  - actual rep count;
  - expected counted timestamp(s);
  - actual counted timestamp(s);
  - timestamp tolerance.
- Trace excerpt for the counted clean rep.
- Any threshold / fixture geometry choices made.

## Reachability / Demo Proof

The lunge acceptance tests must run through the real product path:

```text
Presets/bodyweight_lunge.json
checked-in fixtures
  -> PoseFrameFixtureLoader
  -> ProgramLoader.load(Presets/bodyweight_lunge.json)
  -> EngineTraceRecorder.record(frames:)
  -> EngineTraceFormatter.format(_:)
```

Do not prove acceptance with direct `RepStateMachine`, `SignalEvaluator`, or hand-built output shortcuts.

## Out Of Scope

- Plank preset.
- Push-up or squat retuning unless a regression is exposed.
- Any engine source changes. ESCALATE if lunge cannot be expressed with the current contract.
- `pose_worker/`, model downloads, camera capture, live app wiring, audio, transport, replay UI, plotting, Layer 2, Layer 3, or persistence.

## Stop Conditions

- ESCALATE if the lunge preset cannot be expressed without new engine code.
- ESCALATE if expected lunge count/depth thresholds require a human product judgment rather than synthetic fixture tuning.
- Keep the DSL total and the preset shape identical to the existing Exercise-Program contract.
