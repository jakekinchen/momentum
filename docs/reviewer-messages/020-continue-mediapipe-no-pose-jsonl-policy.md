# Reviewer Decision 020 - MediaPipe No-Pose JSONL Policy

**Date:** 2026-06-03  
**Decision:** CONTINUE

## Evidence Reviewed

- `GOAL.md`
- `docs/autonomous-workflow/`
- `docs/briefs/020-mediapipe-no-pose-jsonl-policy.md`
- `docs/session-logs/020-executor-mediapipe-no-pose-jsonl-policy.md`
- Latest executor commit: `b3ac42d feat: preserve MediaPipe no-pose frames`
- Current git status before reviewer edits: clean, branch ahead of `origin/main`

## Audit Findings

The executor completed the requested no-pose JSONL policy slice within scope.

- Valid `pose_worker` no-pose records now decode to timestamped `PoseFrame` values with preserved image dimensions and `landmarks == [:]`.
- No-pose frames are preserved in the provider timeline rather than filtered out.
- Positive `poses_detected` records still require exactly 33 landmarks.
- Malformed/inconsistent no-pose records fail closed.
- The mixed pose/no-pose/pose fixture proves frame order, no-pose dimensions, empty landmarks, invalid/missing-signal trace evidence, no false count at the no-pose timestamp, and explicit final rep count.
- Existing MediaPipe decode tests and low-visibility fixture tests remain green.
- The slice stayed headless and offline: no Python spawn, model download, camera access, SwiftUI app run, network, Layer 2, or Layer 3 behavior.

One caveat for future hardening: the Swift decoder requires `world_landmarks` to exist but does not yet require exactly 33 world landmarks for positive pose records. That is acceptable for this no-pose slice because the engine currently consumes normalized landmarks only, but a later worker-contract hardening pass should make the full schema strict if world landmarks become relevant.

## Validation Reproduced

```bash
scripts/audit_autonomous_workflow.sh
swift build --disable-sandbox
swift test --disable-sandbox
```

Results:

- Workflow audit: clean.
- Build: completed successfully.
- Full Swift test suite: 64 tests, 0 failures.

Executor evidence retained in the session log:

```text
mediapipe-jsonl-no-pose frames=3 timestamps=[2000, 2100, 2200] no_pose=[2100] size=1280.0x720.0 counted_in_no_pose=0 final_reps=0
mediapipe-jsonl-no-pose-trace
2100 | ready | 0 | false | knee=invalid(...) | ... | invalid=phase signal knee invalid: ...
mediapipe-jsonl-no-pose-inconsistent fail_closed=true
```

Python worker tests were not run because `pytest` is not installed and the active brief correctly forbade `pip install`.

## Routing

Do not move to process-management work yet. The M1 milestone's remaining gate is the squat acceptance suite: exact rep counts, expected count timestamps within tolerance, and no false reps during no-person / low-visibility stretches.

## Next Action

Execute `docs/briefs/021-squat-acceptance-suite.md`.

## Human Escalation

None.
