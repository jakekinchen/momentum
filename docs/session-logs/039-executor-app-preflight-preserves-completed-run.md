# 039 Executor: App Preflight Preserves Completed Run

## Slice

Added one deterministic app-level regression test proving mock-worker preflight updates only preflight status and does not disturb an already completed app run.

This slice is test-only. No product code changed.

## Files Changed

- `Tests/CamiFitAppTests/AppMockWorkerPreflightTests.swift`
- `docs/session-logs/039-executor-app-preflight-preserves-completed-run.md`

## Validation

Focused:

```sh
swift test --disable-sandbox --filter AppMockWorkerPreflightTests
```

Result: passed, 3 tests, 0 failures.

Evidence:

```text
app-mock-worker-preflight-missing path=/Users/kelly/Developer/camifit/pose_worker/missing_pose_worker.py diagnostic=mock worker script not found: /Users/kelly/Developer/camifit/pose_worker/missing_pose_worker.py summary_mutated=false
app-mock-worker-preflight-preserves-run frames=1 overlay_points=37 run_status=mock-worker succeeded: 1 frame(s) success_preserved=true failure_preserved=true
app-mock-worker-preflight-success command=/usr/bin/env python3 /Users/kelly/Developer/camifit/pose_worker/pose_worker.py --mode mock mode=VIDEO message=mock mode ready (synthetic landmarks, no model load) summary_mutated=false
```

Broad:

```sh
swift build --disable-sandbox
```

Result: passed.

```sh
swift test --disable-sandbox
```

Result: passed, 114 tests, 0 failures.

Workflow:

```sh
scripts/audit_autonomous_workflow.sh
```

Result: passed.

Diff hygiene:

```sh
git diff --check -- Tests/CamiFitAppTests/AppMockWorkerPreflightTests.swift
```

Result: passed.

## Reachability

The regression uses the real app view model path:

`AppExerciseSessionViewModel.runMockWorkerProvider(...) -> AppPoseProviderFactory/PoseWorkerSubprocessProvider -> AppPoseProviderSession -> lastPoseProviderRunSummary/latestHUDState/latestPoseOverlayState/poseProviderRunStatus`.

After capturing that completed-run state, the test calls:

- `AppExerciseSessionViewModel.preflightMockWorker(workerScriptURL:)` with the real mock worker path and asserts success.
- `AppExerciseSessionViewModel.preflightMockWorker(workerScriptURL:)` with a missing worker path and asserts failure.

Both preflight calls leave the captured completed-run state unchanged:

```text
app-mock-worker-preflight-preserves-run frames=1 overlay_points=37 run_status=mock-worker succeeded: 1 frame(s) success_preserved=true failure_preserved=true
```

## Boundary Evidence

- Did not launch the live app.
- Did not run live camera capture.
- Did not download models.
- Did not install Python packages.
- Did not modify `pose_worker/`.
- Did not modify UI code.

## Flags For Reviewer

- The existing implementation already preserved completed-run state; this slice locks that behavior with a deterministic regression.
- The test also covers missing-worker preflight after a completed run, because that was a small extension within the brief and confirms failure status is isolated too.
- `ContentView` reachability was not changed in this slice; reachability proof is through the app view model/product command path already wired by prior slices.

## Next Suggested Slice

Add a human-run SwiftUI verification handoff/checklist for the app mock-worker command and preflight status surfaces, or let Reviewer inspect this regression before expanding UI coverage.
