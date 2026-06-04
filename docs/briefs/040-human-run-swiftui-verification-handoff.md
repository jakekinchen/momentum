# Brief 040: Human-Run SwiftUI Verification Handoff

## Objective

Prepare a precise human-run verification handoff for the current SwiftUI app shell controls and mock-worker path.

This is a docs-only slice. The executor must not launch the SwiftUI app, run live camera capture, take screenshots, or claim visual behavior. The output should make it easy for a human/manager to run the app and record what they observe.

## Scope

- Add a handoff document under `docs/manual-verification/` or another existing appropriate docs location.
- Include exact preconditions:
  - current branch/commit;
  - `swift test --disable-sandbox` green as the headless gate;
  - no `pose_worker/` changes required;
  - mock worker uses `pose_worker.py --mode mock`, not live camera.
- Include exact human-run steps for the SwiftUI app shell:
  - launch the app target/package in the repo-local supported way;
  - confirm preset list/control surface appears;
  - click `Check Mock Worker`;
  - observe mock-worker preflight status text;
  - click `Run Mock Worker`;
  - observe provider status, HUD frame count, and skeleton overlay update;
  - verify recorded-run controls still work.
- Include expected observations and failure evidence to capture.
- Include a short section for the human to fill in observed result, date, app launch command, pass/fail, and notes.
- Update the executor session log with commands run and boundary statement.

## Out of Scope

- No product code changes.
- No live camera mode.
- No MediaPipe model download.
- No `pip install`.
- No changes under `pose_worker/`.
- No async streaming or cancellation model.
- No UI redesign.
- No SwiftUI app launch, screenshot, visual verification, or live-camera claim by the executor.
- No Layer 2 agent-authoring or Layer 3 persistence work.

## Acceptance Criteria

- The handoff document exists and is specific enough for a human to run without guessing.
- The handoff separates headless proof from human-observed SwiftUI behavior.
- The handoff includes expected observations for both `Check Mock Worker` and `Run Mock Worker`.
- `scripts/audit_autonomous_workflow.sh` passes.
- `git diff --check` passes.
- If no product code changed, `swift test --disable-sandbox` is optional but preferred if already cheap; do not block this docs-only slice on pytest.

## Logging Requirements

The executor session log must include:

- Files changed.
- Exact validation commands and results.
- A boundary statement confirming no live app launch, screenshot, camera run, `pose_worker/` change, pytest run, model download, or `pip install` occurred.
