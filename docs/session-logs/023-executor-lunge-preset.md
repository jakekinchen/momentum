# Session Log 023 - Executor - Lunge Preset

**Date:** 2026-06-03  
**Role:** Executor  
**Slice:** `docs/briefs/023-lunge-preset.md`  
**Commit:** final scoped slice commit in git history

## Summary

Implemented the lunge M2 preset as a data-only Exercise-Program with checked-in clean and shallow synthetic fixtures plus focused acceptance coverage. The slice stayed inside the brief boundary: no `Sources/CamiFitEngine/`, no `pose_worker/`, no macOS app, no downloads, no network, no Layer 2, and no Layer 3 changes.

## Files Changed

- `Presets/bodyweight_lunge.json`
- `Tests/CamiFitEngineTests/Fixtures/synthetic_lunge_clean_trace.json`
- `Tests/CamiFitEngineTests/Fixtures/synthetic_lunge_shallow_trace.json`
- `Tests/CamiFitEngineTests/LungeAcceptanceTests.swift`
- `docs/session-logs/023-executor-lunge-preset.md`

## Implementation Notes

- Mapped the synthetic side-view front leg to the existing `primary.*` landmark names.
- Used existing supported DSL functions only:
  - `angle(...)`
  - `angle_to_vertical(...)`
  - `abs(...)`
- Added filtered `front_knee` as the lunge phase signal.
- Tuned rep thresholds for deterministic synthetic fixture proof:
  - `down_when`: `front_knee < 105`
  - `up_when`: `front_knee > 160`
  - `min_rom_deg`: `50`
- Added form rules for depth, torso posture, and front-knee tracking using existing `form_rules` semantics.
- Reused the existing compact synthetic side-view geometry pattern:
  - Clean fixture reaches a full 90-degree front-knee bend and returns to standing/top.
  - Shallow fixture never crosses the down threshold and must not count.

## Validation

Focused:

```bash
swift test --disable-sandbox --filter LungeAcceptanceTests
```

Result:

```text
Executed 1 test, with 0 failures (0 unexpected)
lunge-acceptance case=clean frames=17 expected_reps=1 actual_reps=1 expected_counted=[1600] actual_counted=[1600] tolerance_ms=50
lunge-acceptance-trace-clean
1600 | ready | 1 | true | front_knee=valid(173.304, confidence: 1.000),torso_tilt=valid(0.000, confidence: 1.000) | form=none | cue=nil | score=nil | invalid=nil
lunge-acceptance case=shallow frames=9 expected_reps=0 actual_reps=0 expected_counted=[] actual_counted=[] tolerance_ms=50
```

Broad:

```bash
swift build --disable-sandbox
```

Result:

```text
Build complete!
```

```bash
swift test --disable-sandbox
```

Result:

```text
Executed 67 tests, with 0 failures (0 unexpected)
```

Workflow audit:

```bash
scripts/audit_autonomous_workflow.sh
```

Result:

```text
workflow audit clean
```

## Reachability

The acceptance test proves the real product path requested by the brief:

```text
Presets/bodyweight_lunge.json
checked-in fixtures
  -> PoseFrameFixtureLoader
  -> ProgramLoader.load(Presets/bodyweight_lunge.json)
  -> EngineTraceRecorder.record(frames:)
  -> EngineTraceFormatter.format(_:)
```

No acceptance assertion uses `RepStateMachine`, `SignalEvaluator`, or hand-built output shortcuts directly.

## Evidence

- `ProgramLoader.load(from:)` accepts `Presets/bodyweight_lunge.json` and verifies `program.id == "bodyweight_lunge"`.
- Clean fixture:
  - frames: `17`
  - expected reps: `1`
  - actual reps: `1`
  - expected counted timestamps: `[1600]`
  - actual counted timestamps: `[1600]`
  - tolerance: `50ms`
- Shallow fixture:
  - frames: `9`
  - expected reps: `0`
  - actual reps: `0`
  - expected counted timestamps: `[]`
  - actual counted timestamps: `[]`
  - tolerance: `50ms`
- Existing squat and push-up acceptance tests remained green in the full Swift suite.

## Flags For Reviewer

- The lunge fixture is synthetic and uses `primary.*` as the front leg; it proves contract reachability and deterministic thresholds, not live camera ergonomics.
- The tracking rule uses left/right knee-angle agreement because the current DSL has no richer 2D knee-over-toe or side-specific lunge helper. No engine change was made.
- `scripts/audit_autonomous_workflow.sh` showed unrelated untracked `docs/research/` before this slice; it was left untouched and not staged.

## Next Suggested Slice

Proceed to the next M2 data-only preset: plank. Suggested scope is `Presets/bodyweight_plank.json`, checked-in hold fixtures, and acceptance tests that prove hold timing and fail-closed shallow/invalid behavior through the same product path.
