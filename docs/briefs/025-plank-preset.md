# Slice Brief 025 - Plank Preset (M2)

**Date:** 2026-06-03

## Objective

Add a **plank** Exercise-Program as data + golden hold acceptance fixtures, using the newly added `HoldEvaluator` path.

Pure Swift + JSON, offline. Do not modify `Sources/CamiFitEngine/`, `pose_worker/`, the macOS app, network code, or downloads unless a real bug in the just-added hold path is exposed and narrowly fixed.

## Product / Project Value

Plank completes M2's bodyweight preset set: push-up, lunge, and plank. Unlike push-up/lunge, plank exercises hold timing instead of rep counting, proving the Exercise-Program contract now covers both rep and hold exercises.

## Scope

- Add `Presets/bodyweight_plank.json` using the existing Exercise-Program contract:
  - `rep: null`;
  - `hold` config with a filtered hold signal such as `plank_line`;
  - `hold.in_range` expressed with currently supported comparison syntax, for example `plank_line >= 160`;
  - a small target, e.g. `target_seconds: 1.0`, suitable for deterministic fixture tests.
- Suggested signals:
  - `plank_line_raw`: `angle(primary.shoulder, primary.hip, primary.ankle)`;
  - `plank_line`: EMA or median filter over `plank_line_raw`;
  - optional torso/hip-line form signal if expressible with existing DSL.
- Add at least one form rule if it works cleanly with the hold trace path, e.g. sagging hips. If phase-based form activation does not fit hold programs yet, keep form rules minimal or empty and record why in the executor log.
- Add small checked-in synthetic fixtures under `Tests/CamiFitEngineTests/Fixtures/`:
  - `synthetic_plank_clean_hold_trace.json` — continuous in-range hold that reaches the target exactly.
  - `synthetic_plank_broken_hold_trace.json` — out-of-range frame resets held seconds and does not reach target.
  - `synthetic_plank_low_visibility_trace.json` — invalid/low-visibility frame resets held seconds and records invalid evidence.
- Add `Tests/CamiFitEngineTests/PlankAcceptanceTests.swift`:
  - load `bodyweight_plank.json` through `ProgramLoader`;
  - load fixtures through `PoseFrameFixtureLoader`;
  - run `EngineTraceRecorder` and `EngineTraceFormatter`;
  - assert clean target reached at the expected timestamp;
  - assert broken hold resets and never reaches target;
  - assert invalid/low-visibility hold resets, carries a reason, and never reaches target;
  - print acceptance evidence mirroring the existing acceptance style.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass using the default in-repo `.build`.
- `bodyweight_plank.json` loads and validates through `ProgramLoader`.
- Clean fixture proves:
  - exact held seconds by frame, or within a tight explicit tolerance for floating-point formatting;
  - `targetReached == true` at the expected timestamp.
- Broken fixture proves:
  - out-of-range frame resets held seconds to `0`;
  - target is not reached.
- Low-visibility fixture proves:
  - invalid signal resets held seconds to `0`;
  - invalid reason names the low-confidence landmark;
  - target is not reached.
- Existing squat, push-up, lunge, and hold evaluator tests remain green.
- No changes under `pose_worker/`.
- No model download, camera access, SwiftUI app run, network dependency, Layer 2, or Layer 3 behavior is added.

## Expected Files

- `Presets/bodyweight_plank.json`
- `Tests/CamiFitEngineTests/Fixtures/synthetic_plank_clean_hold_trace.json`
- `Tests/CamiFitEngineTests/Fixtures/synthetic_plank_broken_hold_trace.json`
- `Tests/CamiFitEngineTests/Fixtures/synthetic_plank_low_visibility_trace.json`
- `Tests/CamiFitEngineTests/PlankAcceptanceTests.swift`
- `docs/session-logs/025-executor-plank-preset.md`

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
- Focused plank acceptance result.
- Acceptance summary for each fixture:
  - fixture name;
  - frame count;
  - held seconds by timestamp;
  - expected target reached timestamp or `nil`;
  - actual target reached timestamp(s);
  - reset timestamp(s);
  - invalid reason excerpt where applicable.
- Form-rule choice, especially if form rules are omitted because hold programs do not yet expose phase-specific activation semantics.

## Reachability / Demo Proof

The plank acceptance tests must run through the real product path:

```text
Presets/bodyweight_plank.json
checked-in fixtures
  -> PoseFrameFixtureLoader
  -> ProgramLoader.load(Presets/bodyweight_plank.json)
  -> EngineTraceRecorder.record(frames:)
  -> EngineTraceFormatter.format(_:)
```

Do not prove acceptance with direct `HoldEvaluator` calls only.

## Out Of Scope

- Additional exercise presets.
- Retuning squat, push-up, or lunge unless a regression is exposed.
- Broad HoldEvaluator redesign. ESCALATE if plank needs a different hold policy than reset-on-break.
- `pose_worker/`, model downloads, camera capture, live app wiring, audio, transport, replay UI, plotting, Layer 2, Layer 3, or persistence.

## Stop Conditions

- ESCALATE if plank cannot be expressed with the current `HoldEvaluator` and existing DSL comparison syntax.
- ESCALATE if target timing or reset semantics require a human product judgment rather than deterministic fixture expectations.
- Keep the DSL total and the preset shape identical to the existing Exercise-Program contract.
