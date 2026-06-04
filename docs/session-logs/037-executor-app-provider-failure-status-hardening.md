# 037 Executor - App Provider Failure Status Hardening

## Slice

Hardened deterministic status coverage for the remaining app provider failure paths. This was a test-only slice: the existing status implementation already produced stable failed statuses for direct provider failures and configured-provider failures.

## Files Changed

- `Tests/CamiFitAppTests/AppPoseProviderRunStatusTests.swift`
  - Added `testDirectProviderFailureUpdatesFailedStatusWithDeterministicDescriptor`.
  - Added `testConfiguredRecordedRunFailureUpdatesFailedStatusWithRequestedSource`.
  - Added local `StatusThrowingPoseProvider` and `StatusProviderFailure` helpers.

No production code changed.

## Validation

Focused:

```sh
swift test --disable-sandbox --filter AppPoseProviderRunStatusTests
```

Result: passed, 6 tests, 0 failures.

Evidence:

```text
app-provider-status-configured-failure mode=recorded-run source=recorded:missing-recorded-run diagnostic=Pose provider configuration failed: recorded run not found: missing-recorded-run
app-provider-status-direct-failure mode=provider source=direct-provider diagnostic=Pose provider failed: direct provider unavailable
app-provider-status-initial status=Provider idle
app-provider-status-missing-mock mode=mock-worker source=mock-worker:/usr/bin/env python3 /Users/kelly/Developer/camifit/pose_worker/missing_pose_worker.py --mode mock diagnostic=Pose provider failed: pose worker script not found: /Users/kelly/Developer/camifit/pose_worker/missing_pose_worker.py
app-provider-status-mock mode=mock-worker source=mock-worker:/usr/bin/env python3 /Users/kelly/Developer/camifit/pose_worker/pose_worker.py --mode mock frames=1 overlay_points=37
app-provider-status-recorded mode=recorded-run source=recorded:squat_two_frames frames=2
```

Broad:

```sh
swift build --disable-sandbox
swift test --disable-sandbox
scripts/audit_autonomous_workflow.sh
git diff --check -- Tests/CamiFitAppTests/AppPoseProviderRunStatusTests.swift
```

Results:

- `swift build --disable-sandbox`: passed.
- `swift test --disable-sandbox`: passed, 111 tests, 0 failures.
- `scripts/audit_autonomous_workflow.sh`: workflow audit clean.
- `git diff --check`: passed.

## Reachability

Direct provider failure reachability is proven by `testDirectProviderFailureUpdatesFailedStatusWithDeterministicDescriptor`:

```text
AppExerciseSessionViewModel.runRecordedProvider(throwingProvider, selectedPresetID: "bodyweight_squat")
-> AppPoseProviderSession
-> provider.frames() throws
-> AppPoseProviderRunSummary(diagnosticText: "Pose provider failed: direct provider unavailable")
-> AppHUDState(diagnosticText preserved)
-> AppPoseProviderRunStatus.failed(mode=provider, source=direct-provider)
```

Configured provider failure reachability is proven by `testConfiguredRecordedRunFailureUpdatesFailedStatusWithRequestedSource`:

```text
AppExerciseSessionViewModel.runConfiguredPoseProvider(mode: .recordedRun(id: "missing-recorded-run"))
-> AppPoseProviderFactory.configuredProvider(for:)
-> AppPoseProviderFactoryError.recordedRunNotFound
-> AppPoseProviderRunSummary(diagnosticText: "Pose provider configuration failed: recorded run not found: missing-recorded-run")
-> AppHUDState(diagnosticText preserved)
-> AppPoseProviderRunStatus.failed(mode=recorded-run, source=recorded:missing-recorded-run)
```

## Boundary Statement

No live app launch, screenshot, camera run, `pose_worker/` change, pytest run, MediaPipe model download, or `pip install` occurred. This slice only added deterministic failure-status tests.

## Flags For Reviewer

- No product code changed; the existing implementation already satisfied the failure descriptor contract.
- Direct provider status uses `mode=provider`, `source=direct-provider`.
- Configured missing recorded-run status uses `mode=recorded-run`, `source=recorded:<requested-id>`.

## Next Suggested Slice

Begin a minimal app-side mock-worker preflight status slice, or prepare a reviewer/manager handoff for human-run SwiftUI verification of the accumulated app command surface.
