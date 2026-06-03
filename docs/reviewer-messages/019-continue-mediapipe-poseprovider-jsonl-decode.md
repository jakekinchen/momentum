# Reviewer Decision 019 - MediaPipe PoseProvider JSONL Decode

**Date:** 2026-06-03  
**Decision:** CONTINUE

## Evidence Reviewed

- `GOAL.md`
- `docs/autonomous-workflow/`
- `docs/briefs/019-mediapipe-poseprovider-jsonl-decode.md`
- `docs/session-logs/019-executor-mediapipe-poseprovider-jsonl-decode.md`
- Latest executor commit: `7de4287 feat: decode MediaPipe pose JSONL`
- Current git status before reviewer edits: clean, branch ahead of `origin/main`
- `pose_worker/pose_worker.py`, `pose_worker/README.md`, and `pose_worker/tests/test_pose_worker.py` schema references

## Audit Findings

The executor completed the requested headless MediaPipe JSONL decode slice within scope.

- Added a minimal `PoseProvider` boundary and `MediaPipePoseProvider(jsonlURL:)`.
- Added `MediaPipePoseJSONLDecoder` for line-delimited `pose_worker` records.
- Added a small checked-in JSONL fixture matching the worker's `pose` output shape with 33 ordered landmarks.
- Mapped ordered MediaPipe landmarks into engine names including right/left side names and `primary.*`.
- Preserved timestamps, image dimensions, `x/y/z`, visibility, and presence; documented and tested `presence = visibility` fallback.
- Failed closed for malformed JSON and wrong landmark counts.
- Proved decoded frames reach `EngineTraceRecorder` and `EngineTraceFormatter` through the real squat preset.
- Stayed offline: no Python spawn, model download, camera access, SwiftUI app run, network, Layer 2, or Layer 3 behavior.

The executor flagged two policy areas:

- The first `primary.*` alias policy chooses the side with higher mean confidence across shoulder/hip/knee/ankle, tie-breaking to right. This is acceptable as a deterministic first boundary and remains easy to revise if live/recorded data shows a better rule is needed.
- The worker's valid no-pose schema emits `poses_detected:0`, `primary_pose_id:null`, and empty `landmarks` / `world_landmarks`. The current Swift decoder intentionally fails wrong landmark counts, so no-pose handling is not yet represented. This was not required by brief 019, but it is the right next headless policy slice before process/live wiring.

## Validation Reproduced

```bash
scripts/audit_autonomous_workflow.sh
swift build --disable-sandbox
swift test --disable-sandbox
```

Results:

- Workflow audit: clean.
- Build: completed successfully.
- Full Swift test suite: 62 tests, 0 failures.

Executor evidence retained in the session log:

```text
mediapipe-jsonl-decode frames=2 timestamps=[1000, 1100] size=1280.0x720.0 primary_knee=Optional(...)
mediapipe-jsonl-presence-fallback right_knee_presence=0.96
mediapipe-jsonl-fail-closed malformed=true wrong_count=true
mediapipe-jsonl-trace frames=2 trace=2
```

Python worker tests were not run because `pytest` is not installed and the active brief correctly forbade unapproved package installation.

## Routing

Advance to a process-free no-pose JSONL policy slice. The planner decision is: preserve no-pose records as timestamped `PoseFrame` values with empty landmarks, so the engine sees the time step, produces invalid/missing-signal evidence, and cannot count false reps. Do not silently drop no-pose frames in the provider layer.

## Next Action

Execute `docs/briefs/020-mediapipe-no-pose-jsonl-policy.md`.

## Human Escalation

None.
