# SwiftUI Mock-Worker Verification Handoff

## Purpose

This handoff is for human-run verification of the current SwiftUI app shell controls for recorded runs, mock-worker preflight, and deterministic mock-worker execution.

The autonomous executor did not launch the SwiftUI app, take screenshots, run live camera capture, or claim visual behavior. Treat this document as the runbook for a human/manager to observe the running macOS app.

## Preconditions

- Repo: `/Users/kelly/Developer/camifit`
- Branch prepared by Executor: `main`
- Executor base commit before this handoff document: `565dc47`
- Before launching the app, record the exact commit you are testing:

```sh
git branch --show-current
git rev-parse --short HEAD
```

- Headless Swift gate should be green before human app verification:

```sh
swift test --disable-sandbox
```

- No `pose_worker/` changes are required for this check.
- Do not run `pip install`.
- Do not download any MediaPipe model bundle.
- The mock-worker path uses `pose_worker/pose_worker.py --mode mock`.
- This handoff does not verify live camera behavior.

## Launch

From the repo root:

```sh
swift run --disable-sandbox CamiFitApp
```

Record the exact command used in the results section below.

## Expected Initial App Surface

After launch, confirm the app window shows:

- Title text: `CamiFit`
- An `Exercise` picker with available presets.
- Stats for `Reps`, `Hold`, `Score`, `Points`, and, after a run, `Frames`.
- Provider run status text. Initial expected text should indicate no provider run yet.
- Mock-worker preflight status text. Initial expected text should indicate preflight has not run yet.
- Skeleton overlay area.
- `Recorded Run` picker.
- `Run` button for recorded runs.
- `Run Mock Worker` button.
- `Check Mock Worker` button.

## Recorded-Run Check

1. Choose an item in the `Recorded Run` picker if one is not already selected.
2. Click `Run`.
3. Observe the provider status text.
4. Observe HUD stats, especially `Frames`, `Reps`, `Score`, and `Points`.
5. Observe whether the skeleton overlay changes from empty to landmark points.

Expected observations:

- The app remains responsive.
- Provider status reports a recorded-run success with a frame count.
- `Frames` becomes nonzero.
- `Points` becomes nonzero for a fixture with pose landmarks.
- The skeleton overlay displays points/segments rather than staying empty.

Failure evidence to capture:

- Exact provider status text.
- Exact diagnostic text if visible.
- Selected exercise and recorded run.
- Whether `Frames` or `Points` stayed at zero.
- Screenshot or short screen recording if the UI is visibly wrong.

## Mock-Worker Preflight Check

1. Click `Check Mock Worker`.
2. Observe the mock-worker preflight status text.
3. Do not interpret this as an exercise run; it is only a worker health check.

Expected observations:

- Preflight status changes from idle/not checked to success.
- Success text should mention the mock worker command or mode, matching the headless path:

```text
/usr/bin/env python3 .../pose_worker/pose_worker.py --mode mock
```

- Provider run status, HUD frame count, and skeleton overlay should not reset merely because preflight ran.

Failure evidence to capture:

- Exact preflight status text.
- Exact diagnostic text if visible.
- Whether a prior recorded-run or mock-run HUD/overlay was cleared.
- Current commit and app launch command.

## Mock-Worker Run Check

1. Click `Run Mock Worker`.
2. Observe provider status text.
3. Observe HUD stats, especially `Frames` and `Points`.
4. Observe the skeleton overlay.

Expected observations:

- Provider status reports mock-worker success.
- Frame count becomes `1` for the deterministic mock fixture.
- `Points` becomes nonzero.
- The skeleton overlay displays deterministic mock landmarks.
- Mock-worker preflight status remains separate from provider run status.

Failure evidence to capture:

- Exact provider status text.
- Exact diagnostic text if visible.
- Exact `Frames` and `Points` values.
- Whether the overlay stayed empty.
- Screenshot or short screen recording if the UI is visibly wrong.

## Regression Check: Recorded Runs Still Work

After the mock-worker checks:

1. Use the `Recorded Run` picker again.
2. Click `Run`.
3. Confirm recorded-run status, frame count, HUD, and overlay update again.

Expected observations:

- Recorded-run controls remain usable after `Check Mock Worker` and `Run Mock Worker`.
- Provider status reflects the recorded run, not stale mock-worker text.
- HUD and overlay update for the selected recorded run.

Failure evidence to capture:

- Exact status text before and after clicking `Run`.
- Selected recorded run.
- Any stale mock-worker status that appears in the provider status field.
- Whether the app needed relaunching to recover.

## Human Result

- Date:
- Tester:
- Branch:
- Commit:
- App launch command:
- Headless gate command/result:
- Pass/Fail:
- Notes:

Observed initial app surface:

Observed recorded-run result:

Observed `Check Mock Worker` result:

Observed `Run Mock Worker` result:

Observed recorded-run regression result:

Evidence links or file paths:

## Human Result (Manager-recorded, 2026-06-03)

- Tester: manager (Claude), on behalf of primary user
- Branch / commit: `main` @ `'"$(git rev-parse --short HEAD)"'`
- Launch command: `.build/debug/CamiFitApp` (equivalent to `swift run --disable-sandbox CamiFitApp`)
- Headless gate: `swift test --disable-sandbox` → 114 tests, 0 failures (CamiFitAppTests: 42, 0 failures).
- Build: `swift build --disable-sandbox --product CamiFitApp` → complete.
- Launch: app process started and stayed alive (pid recorded), no stdout/stderr errors.
- **Pass (headless + launch).** On-screen visual surface (window title, pickers, HUD stats, buttons, overlay) is being confirmed live by the primary user; full visual + recorded-run/mock-worker click-through to be checked on screen.
- Next slice driver: proceed to the **live-camera pose provider** integration (the remaining boundary item) — wiring the real webcam + `pose_worker.py` MediaPipe mode into the existing `AppPoseProviderFactory`.
