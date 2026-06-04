# Brief 032: App Overlay Rendering Surface

## Objective

Add a lightweight SwiftUI pose-overlay rendering surface that consumes `AppPoseOverlayState` and can be wired into the current app shell without claiming live visual verification. This should turn the headless overlay state from brief 031 into a reusable view component for M3.

## Scope

- Add a small SwiftUI view, such as `PoseOverlayView`, that accepts `AppPoseOverlayState`.
- Render normalized overlay points and named segments in a deterministic coordinate space using `GeometryReader`, `Canvas`, `Shape`, or simple SwiftUI primitives.
- Keep the view passive: it should not own camera/provider/session state and should not run the engine.
- Wire the view into `ContentView` in a narrow way using `viewModel.latestPoseOverlayState`, preferably with an explicit fixed or responsive preview area.
- Add tests for any pure geometry/layout mapping helper used by the view, such as normalized point to viewport coordinate conversion and empty-state segment omission.
- Preserve the existing recorded-run command path and HUD state tests.

## Out Of Scope

- No live camera capture.
- No `pose_worker.py` changes.
- No model downloads, `pip install`, or dependency installation.
- No screenshot/browser/app-run verification.
- No claim that the SwiftUI overlay is visually correct in the running macOS app.
- No major UI redesign.

## Acceptance Criteria

- A reusable app-layer overlay view exists and compiles in the `CamiFitApp` target.
- The view consumes `AppPoseOverlayState` rather than raw `PoseFrame` or engine internals.
- Pure geometry tests prove normalized coordinates map deterministically into a target rectangle.
- Empty overlay state produces no drawable points/segments through the tested mapping layer.
- Existing `AppHUDOverlayStateTests`, app recorded-run tests, and full Swift suite remain green.
- The executor session log explicitly states that live visual overlay behavior was not verified.

## Expected Files

- `Sources/CamiFitApp/PoseOverlayView.swift` or similar.
- Optional small pure helper/model file if needed for testable coordinate mapping.
- `Sources/CamiFitApp/ContentView.swift`.
- `Tests/CamiFitAppTests/PoseOverlayViewTests.swift` or similar.
- `docs/session-logs/032-executor-app-overlay-rendering-surface.md`.

## Validation

Run and record:

```sh
swift build --disable-sandbox
swift test --disable-sandbox --filter PoseOverlayViewTests
swift test --disable-sandbox
git diff --check
```

If the focused test name differs, record the exact command used.

## Session Log Requirements

In `docs/session-logs/032-executor-app-overlay-rendering-surface.md`, include:

- Files changed.
- Rendering approach and geometry mapping summary.
- Focused and full validation commands with outcomes.
- Evidence that empty overlay state maps to no drawables.
- Evidence that clean recorded-run overlay state can feed the view's mapping layer.
- Explicit note that no live SwiftUI visual verification was performed or claimed.
