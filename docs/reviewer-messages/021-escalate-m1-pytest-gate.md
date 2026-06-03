# Reviewer Decision 021 - Squat Acceptance Suite

**Date:** 2026-06-03  
**Decision:** ESCALATE  
**Evidence Anchor:** 75

## Evidence Reviewed

- `GOAL.md`
- `docs/autonomous-workflow/`
- `docs/autonomous-workflow/09-autonomous-milestones.md`
- `docs/briefs/021-squat-acceptance-suite.md`
- `docs/session-logs/021-executor-squat-acceptance-suite.md`
- Latest executor commit: `eeeaa12 test: add squat acceptance suite`
- Current git status before reviewer edits: clean, branch ahead of `origin/main`

## Audit Findings

The executor completed the requested squat acceptance-suite slice within scope.

- Added `Tests/CamiFitEngineTests/SquatAcceptanceTests.swift`.
- Added a small shallow fixture at `Tests/CamiFitEngineTests/Fixtures/synthetic_squat_shallow_trace.json`.
- Covered clean, shallow / insufficient-ROM, low-visibility, and MediaPipe no-pose acceptance cases.
- Ran every case through the real product path: checked-in fixture decode/load, `ProgramLoader.load(Presets/bodyweight_squat.json)`, `EngineTraceRecorder.record(frames:)`, and `EngineTraceFormatter.format(_:)`.
- Asserted exact final rep counts.
- Asserted clean counted timestamp `[1600]` within explicit `50ms` tolerance.
- Asserted no false counted reps in low-visibility and no-pose invalid intervals.
- Preserved formatted trace evidence for low-confidence and missing-landmark invalid intervals.
- Stayed headless and offline: no Python spawn, model download, camera access, SwiftUI app run, network, Layer 2, or Layer 3 behavior.

## Validation Reproduced

```bash
scripts/audit_autonomous_workflow.sh
swift build --disable-sandbox
swift test --disable-sandbox --filter SquatAcceptanceTests
swift test --disable-sandbox
python3 -m pytest pose_worker/tests -q
```

Results:

- Workflow audit: clean.
- Build: completed successfully.
- Focused acceptance test: 1 test, 0 failures.
- Full Swift test suite: 65 tests, 0 failures.
- Python worker gate: blocked because the active Python does not have `pytest`.

Python gate output:

```text
/opt/homebrew/opt/python@3.14/bin/python3.14: No module named pytest
```

Acceptance evidence reproduced:

```text
squat-acceptance case=clean frames=17 expected_reps=1 actual_reps=1 expected_counted=[1600] actual_counted=[1600] tolerance_ms=50 invalid_interval=nil false_counts_invalid=0
squat-acceptance case=shallow frames=9 expected_reps=0 actual_reps=0 expected_counted=[] actual_counted=[] tolerance_ms=50 invalid_interval=nil false_counts_invalid=0
squat-acceptance case=low_visibility frames=5 expected_reps=0 actual_reps=0 expected_counted=[] actual_counted=[] tolerance_ms=50 invalid_interval=100...300 false_counts_invalid=0
squat-acceptance case=mediapipe_no_pose frames=3 expected_reps=0 actual_reps=0 expected_counted=[] actual_counted=[] tolerance_ms=50 invalid_interval=2100...2100 false_counts_invalid=0
```

## Escalation Reason

M1's milestone verification gate requires:

```bash
swift test --disable-sandbox
pytest pose_worker/tests
```

The Swift half is now green, including the squat acceptance suite. The Python worker half cannot currently run because `pytest` is missing. The active workflow also says to stop or escalate before `pip install` unless explicitly authorized by the active brief, and brief 021 says not to attempt `pip install`.

This is now a manager/human environment decision, not a product-code decision.

## Decision Needed

Choose one path:

1. Authorize a specific Python test environment command for this repo, such as creating/using a virtualenv and installing `pytest` if needed.
2. Provide an existing local Python environment where `pytest pose_worker/tests` should run.
3. Explicitly defer the Python worker gate and keep M1 marked not complete.

Do not route to M2 or M3 until this gate decision is resolved.

## Next Action

No next executor brief is written because the workflow is escalated at the milestone verification gate.
