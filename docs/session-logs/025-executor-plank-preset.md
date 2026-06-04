# Session Log 025 - Executor - Plank Preset

**Date:** 2026-06-03  
**Role:** Executor  
**Slice:** `docs/briefs/025-plank-preset.md`  
**Commit:** final scoped slice commit in git history

## Summary

Implemented the M2 plank preset as data plus golden hold acceptance fixtures. The slice uses the existing `HoldEvaluator` product path added in slice 024 and stays within the brief boundary: no `Sources/CamiFitEngine/`, no `pose_worker/`, no app, no downloads, no network, no Layer 2, and no Layer 3 changes.

## Files Changed

- `Presets/bodyweight_plank.json`
- `Tests/CamiFitEngineTests/Fixtures/synthetic_plank_clean_hold_trace.json`
- `Tests/CamiFitEngineTests/Fixtures/synthetic_plank_broken_hold_trace.json`
- `Tests/CamiFitEngineTests/Fixtures/synthetic_plank_low_visibility_trace.json`
- `Tests/CamiFitEngineTests/PlankAcceptanceTests.swift`
- `docs/session-logs/025-executor-plank-preset.md`

## Implementation Notes

- Added `bodyweight_plank` with `rep: null` and a `hold` config:
  - `signal`: `plank_line`
  - `in_range`: `plank_line >= 160`
  - `target_seconds`: `1.0`
- Used current supported DSL comparison syntax only; no `between` or new DSL surface.
- Added `plank_line_raw = angle(primary.shoulder, primary.hip, primary.ankle)`.
- Used EMA filtering with `alpha: 1` for deterministic fixture expectations.
- Added one hold-compatible form rule:
  - `hip_line`
  - active when `phase == 'ready'`
  - expects `plank_line >= 160`
  - emits `Lift your hips` on the broken fixture.
- The hold trace path uses a synthetic `.ready` phase for hold programs, so the form rule is intentionally simple and not phase-specific beyond `ready`.

## Validation

Focused:

```bash
swift test --disable-sandbox --filter PlankAcceptanceTests
```

Result:

```text
Executed 1 test, with 0 failures (0 unexpected)
plank-acceptance case=clean frames=3 held=0:0.000:target=false,500:0.500:target=false,1000:1.000:target=true expected_target=[1000] actual_target=[1000] expected_resets=[] actual_resets=[]
plank-acceptance case=broken frames=5 held=0:0.000:target=false,500:0.500:target=false,1000:0.000:target=false,1500:0.000:target=false,2000:0.500:target=false expected_target=[] actual_target=[] expected_resets=[1000] actual_resets=[1000]
plank-acceptance case=low_visibility frames=5 held=0:0.000:target=false,500:0.500:target=false,1000:0.000:target=false,1500:0.000:target=false,2000:0.500:target=false expected_target=[] actual_target=[] expected_resets=[1000] actual_resets=[1000]
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
Executed 72 tests, with 0 failures (0 unexpected)
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

The plank acceptance test proves the real product path requested by the brief:

```text
Presets/bodyweight_plank.json
checked-in fixtures
  -> PoseFrameFixtureLoader
  -> ProgramLoader.load(Presets/bodyweight_plank.json)
  -> EngineTraceRecorder.record(frames:)
  -> EngineTraceFormatter.format(_:)
```

The acceptance assertions inspect `EngineTraceFrame.hold` and formatted trace output produced by the recorder path, not direct `HoldEvaluator` calls.

## Evidence

Clean fixture:

- frames: `3`
- held seconds:
  - `0ms`: `0.000`, target `false`
  - `500ms`: `0.500`, target `false`
  - `1000ms`: `1.000`, target `true`
- expected target reached timestamp: `[1000]`
- actual target reached timestamp: `[1000]`
- reset timestamps: `[]`

Broken fixture:

- frames: `5`
- held seconds:
  - `0ms`: `0.000`
  - `500ms`: `0.500`
  - `1000ms`: `0.000`
  - `1500ms`: `0.000`
  - `2000ms`: `0.500`
- expected target reached timestamp: `[]`
- actual target reached timestamp: `[]`
- reset timestamps: `[1000]`
- reason excerpt: `hold signal plank_line out of range`
- form evidence: `hip_line:fail`, cue `Lift your hips`

Low-visibility fixture:

- frames: `5`
- held seconds:
  - `0ms`: `0.000`
  - `500ms`: `0.500`
  - `1000ms`: `0.000`
  - `1500ms`: `0.000`
  - `2000ms`: `0.500`
- expected target reached timestamp: `[]`
- actual target reached timestamp: `[]`
- reset timestamps: `[1000]`
- reason excerpt: `low confidence landmark primary.hip`
- formatted output includes `plank_line=invalid(...)` and `hip_line:invalid`.

Trace excerpt:

```text
1000 | ready | 0 | false | plank_line=valid(180.000, confidence: 1.000) | held=1.000,in_range=true,valid=true,target=true,reason=nil | hip_line:pass | cue=nil | score=1.000 | invalid=nil
1000 | ready | 0 | false | plank_line=valid(96.026, confidence: 1.000) | held=0.000,in_range=false,valid=true,target=false,reason=hold signal plank_line out of range | hip_line:fail | cue=hip_line:Lift your hips | score=0.000 | invalid=nil
1000 | ready | 0 | false | plank_line=invalid(filter plank_line source plank_line_raw invalid: low confidence landmark primary.hip visibility=0.2 presence=1.0 threshold=0.65) | held=0.000,in_range=false,valid=false,target=false,reason=hold signal plank_line invalid: filter plank_line source plank_line_raw invalid: low confidence landmark primary.hip visibility=0.2 presence=1.0 threshold=0.65 | hip_line:invalid | cue=nil | score=nil | invalid=nil
```

## Flags For Reviewer

- The plank target is deliberately `1.0s` so fixture expectations remain compact and deterministic.
- The form rule uses `phase == 'ready'` because hold programs currently expose a synthetic ready phase through the trace path; richer hold-specific form activation can be a later contract enhancement if needed.
- Existing unrelated untracked files were present and left untouched:
  - `docs/prd/`
  - `docs/research/2026-06-03-chatgpt-pro-pose-stack-response.md`
  - `docs/research/2026-06-03-chatgpt-pro-pose-stack-source-links.json`

## Next Suggested Slice

M2 presets are now present for push-up, lunge, and plank. Suggested next slice: reviewer/manager should decide whether to mark M2 complete or route to M3 integrated macOS app wiring with an exercise picker and live HUD path behind headless unit-tested pieces.
