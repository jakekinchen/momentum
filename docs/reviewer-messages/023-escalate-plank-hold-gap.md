# Reviewer Decision 023 - Lunge Preset

**Date:** 2026-06-03  
**Decision:** ESCALATE  
**Evidence Anchor:** 75

## Evidence Reviewed

- `GOAL.md`
- `docs/autonomous-workflow/`
- `docs/autonomous-workflow/09-autonomous-milestones.md`
- `docs/briefs/023-lunge-preset.md`
- `docs/session-logs/023-executor-lunge-preset.md`
- Latest executor commit: `af6be1c feat: add lunge preset`
- Current git status before reviewer edits: clean except unrelated untracked `docs/research/`

## Audit Findings

The executor completed the requested lunge preset slice within scope.

- Added `Presets/bodyweight_lunge.json`.
- Added clean and shallow lunge fixtures.
- Added `LungeAcceptanceTests` that load the preset through `ProgramLoader`, load fixtures through `PoseFrameFixtureLoader`, and run the product path through `EngineTraceRecorder` and `EngineTraceFormatter`.
- Asserted clean exact rep count `1` and counted timestamp `[1600]` within `50ms`.
- Asserted shallow exact rep count `0`.
- Used supported DSL functions only: `angle(...)`, `angle_to_vertical(...)`, and `abs(...)`.
- Kept the slice data/test-only: no `Sources/CamiFitEngine/`, `pose_worker/`, app, network, download, or install changes.

## Validation Reproduced

```bash
scripts/audit_autonomous_workflow.sh
swift build --disable-sandbox
swift test --disable-sandbox --filter LungeAcceptanceTests
swift test --disable-sandbox
```

Results:

- Workflow audit: clean.
- Build: completed successfully.
- Focused lunge acceptance test: 1 test, 0 failures.
- Full Swift test suite: 67 tests, 0 failures.

Acceptance evidence reproduced:

```text
lunge-acceptance case=clean frames=17 expected_reps=1 actual_reps=1 expected_counted=[1600] actual_counted=[1600] tolerance_ms=50
lunge-acceptance-trace-clean
1600 | ready | 1 | true | front_knee=valid(173.304, confidence: 1.000),torso_tilt=valid(0.000, confidence: 1.000) | form=none | cue=nil | score=nil | invalid=nil
lunge-acceptance case=shallow frames=9 expected_reps=0 actual_reps=0 expected_counted=[] actual_counted=[] tolerance_ms=50
```

## Escalation Reason

The next M2 slice is plank, but the durable milestone and codebase currently conflict:

- `docs/autonomous-workflow/09-autonomous-milestones.md` says M2 ships push-up, lunge, and plank with **NO new engine architecture**, and explicitly says plank exercises the hold/timer path.
- The repo has `HoldConfig` and `ProgramLoader` validation for `hold`, but no `HoldEvaluator`, no hold accumulation in `EngineTraceRecorder`, and no hold acceptance path in tests.
- Therefore a real plank preset cannot currently prove hold timing without changing engine source, while the M2 milestone forbids new engine architecture.

This is a manager/human planning decision, not an executor implementation bug.

## Decision Needed

Choose one path before the next executor slice:

1. Authorize a scoped hold-evaluator engine slice before plank, treating it as completing planned contract surface rather than new architecture.
2. Rewrite M2 so plank is deferred until after a hold-evaluator milestone.
3. Define plank's first slice as a non-hold placeholder preset, accepting that it will not satisfy the current M2 verification wording.

Do not start a plank preset brief until this hold-path decision is resolved.

## Next Action

No next executor brief is written because the workflow is escalated at the plank/hold milestone boundary.
