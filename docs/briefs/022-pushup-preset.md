# Slice Brief 022 - Push-up preset (M2)

**Date:** 2026-06-03

## Objective

Add a **push-up** Exercise-Program as data + a golden acceptance suite, proving the data-driven contract handles a second exercise with **no new engine architecture**. Mirror the existing squat vertical: preset JSON + synthetic landmark fixtures + an acceptance test.

Pure Swift + JSON, offline. Do not modify `pose_worker/` (keeps the slice on the `swift test` gate only).

## Product / Project Value

Push-up is the first M2 preset. If the engine counts push-ups correctly from a hand-authored program with zero new Swift logic, the data-driven contract is validated as the extension mechanism every later exercise (and the agent in Layer 2) relies on.

## Scope

- `Presets/bodyweight_pushup.json` — an Exercise-Program built on the existing contract:
  - signals from elbow angle: `angle(shoulder, elbow, wrist)` per side, combined (e.g. `min`) into a filtered `elbow` signal; a torso/body-line signal for a form rule.
  - `rep`: `down_when` ~ elbow `< 95`, `up_when` ~ elbow `> 150`, with `min_rom_deg`, dwell timing, and cooldown consistent with the squat preset's structure.
  - `form_rules`: at least one (e.g. depth at bottom, and body-line straightness) with timing + cue + score_weight, mirroring squat.
  - `view`, `setup`, `landmark_aliases`, `validity` blocks consistent with `Presets/bodyweight_squat.json`.
- Synthetic fixtures mirroring the squat ones, in `Tests/CamiFitEngineTests/Fixtures/`:
  - `synthetic_pushup_clean_trace.json` — N full reps, no false counts.
  - `synthetic_pushup_shallow_trace.json` — shallow/partial reps that must NOT count.
- `Tests/CamiFitEngineTests/PushupAcceptanceTests.swift` — load the preset, run the fixtures through the same path the squat acceptance suite uses (`PoseFrameFixtureLoader` → `EngineTraceRecorder`/`EngineTraceFormatter`), and assert: exact final rep count on clean; zero counted reps on shallow; no counted rep during any invalid/low-visibility frame.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass (default in-repo `.build`).
- `bodyweight_pushup.json` loads + validates through `ProgramLoader` (no load errors).
- Clean fixture asserts the exact expected rep count; shallow fixture asserts 0 counted reps.
- No new files under `Sources/CamiFitEngine/` are required (data + fixtures + test only). If a genuine engine gap is found, ESCALATE rather than widening scope silently.

## Expected Files

- `Presets/bodyweight_pushup.json`
- `Tests/CamiFitEngineTests/Fixtures/synthetic_pushup_clean_trace.json`
- `Tests/CamiFitEngineTests/Fixtures/synthetic_pushup_shallow_trace.json`
- `Tests/CamiFitEngineTests/PushupAcceptanceTests.swift`
- `docs/session-logs/022-executor-pushup-preset.md`

## Validation Commands

```bash
cd ~/Developer/camifit
swift build --disable-sandbox
swift test  --disable-sandbox
```

## Out Of Scope

- Lunge and plank presets (briefs 023, 024).
- Any change to `pose_worker/`, the engine `Sources/`, the macOS app, network, or downloads.

## Stop Conditions

- ESCALATE if the push-up preset cannot be expressed without new engine code (that would be a real contract gap worth surfacing).
- Keep the DSL total and the preset shape identical to the squat contract.
