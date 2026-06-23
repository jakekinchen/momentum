# Goal Loop Ledger

Objective:
Build the first concrete slice of the Momentum/CamiFit motion-data factory so bad exercise motion cannot be silently promoted from "detector produced landmarks" to "product-trustworthy motion." The loop should turn `docs/research/2026-06-23-motion-data-pipeline-deep-dive.md` into executable repo scaffolding, validation/reporting, and review guidance.

Started:
2026-06-23

Cadence:
Iterate locally until either the done criteria pass or a hard blocker repeats for three materially identical iterations.

Owner constraints:
- Work only in `/Users/kelly/Developer/camifit-app-agent-motion-data-factory`.
- Target branch is `agent/motion-data-factory-goal-loop`.
- Base branch is `main` at `f5b2c30`.
- The live checkout at `/Users/kelly/Developer/camifit-app` has unrelated dirty files. Do not touch, restore, overwrite, or depend on that checkout.
- Do not delete or rename `/Users/kelly/Developer/camifit` or `/Users/kelly/Developer/camifit-pose`.
- Do not promote any `reference_capture_required` exercise to guide-ready.
- Do not modify packaged `Sources/CamiFitApp/Resources/MotionDemos/*.jsonl` unless the change is only to add explicit non-promotional metadata or tests prove it is required.

Authorized mutations:
- `scripts/motion_reference/**`
- `docs/research/**`
- `docs/manual-verification/**`
- `website/src/app/motion-review/**`
- `website/src/lib/motionReview.ts`
- focused tests under `scripts/motion_reference/test_*.py`

## Done Criteria

- A repo-local motion-data factory preflight exists and can classify exercises into explicit promotion tiers, including at least:
  - recommendation-only
  - source-candidate
  - detector-reviewable
  - avatar-demo-candidate
  - guide-ready
  - validation-ready
- The preflight has hard, machine-readable reasons for why an exercise is not guide-ready or validation-ready.
- The preflight does not merely duplicate `report_motion_pipeline_gaps.py`; it must add at least one new factory concept from the deep-dive, such as capture session metadata, detector agreement scorecards, kinematic scorecards, or explicit human visual-review decisions.
- Any new schemas, examples, or scorecard contracts are documented and covered by tests.
- Existing guide-ready exercises remain guide-ready unless a real discovered defect is documented as a blocker.
- No bad or pending visual-review exercise is promoted.
- All relevant local proof commands pass, or the loop exits blocked with exact failing command output and a minimal unblock plan.

## Proof Target

- Surface:
  motion-reference pipeline scripts, tests, and review docs.
- Required commands:
  - `python3 -m py_compile scripts/motion_reference/*.py`
  - `python3 scripts/motion_reference/test_report_motion_pipeline_gaps.py`
  - any new `scripts/motion_reference/test_*.py` added by this work
  - `python3 scripts/motion_reference/report_motion_pipeline_gaps.py`
  - the new preflight/report command added by this loop
- Required result:
  all commands exit 0, and the new report exposes actionable tier/reason output for the current 15 exercise rows.

## Current State

- Last proof:
  Parent thread generated `tmp/motion-review-deep-dive/gap-report.json`.
- Last result:
  Current report shows 15 exercise rows, 4 playable JSONLs, 4 guide-ready IDs, 11 reference-capture-required IDs, 4 blocked visual-review rows, and 4 guide-ready traces relying on local-only `dist/` source-chain artifacts.
- Known blockers:
  Actual new first-party video capture cannot happen inside this loop unless source files already exist locally. If capture is required, exit with a capture checklist and exact next capture pack contract instead of fabricating data.

## Iterations

| Time | Action | Proof | Result | Next Step |
| --- | --- | --- | --- | --- |
| 2026-06-23 16:07 CDT | Read AGENTS.md, GOAL.md, the motion-data deep dive, motion-reference README, existing gap/audit scripts, and confirmed the isolated worktree/branch. | `git status --short --branch`; `git worktree list --porcelain`; source reads of `report_motion_pipeline_gaps.py`, `audit_motion_coverage.py`, `audit_kg_motion_readiness.py`, manifests, and profile registry. | Target worktree is `/Users/kelly/Developer/camifit-app-agent-motion-data-factory` on `agent/motion-data-factory-goal-loop` at `f5b2c30`; only `GOAL.md` is modified as the loop ledger. Current app gate has 4 guide-ready IDs and 11 reference-capture-required IDs; the first slice should reuse the gap/audit facts while adding factory-specific capture/review/scorecard gates. | Add a repo-local motion-data factory preflight/report, JSON schema contracts, focused tests, and docs without modifying packaged MotionDemos. |
| 2026-06-23 16:13 CDT | Added `preflight_motion_data_factory.py`, scorecard/capture/report schemas, unit tests, README docs, and manual verification guidance. | `python3 -m py_compile scripts/motion_reference/*.py`; `python3 scripts/motion_reference/test_preflight_motion_data_factory.py`; `python3 scripts/motion_reference/preflight_motion_data_factory.py`. | Initial proof passed. Preflight reports 15 exercise rows, 4 guide-ready, 0 validation-ready, 6 source-candidate, 5 avatar-demo-candidate, and 11 blocked from guide-ready. Existing guide-ready IDs remain guide-ready; reference-capture-required rows stay below guide-ready. | Run the full GOAL proof target, fix any failures, then commit locally if all done criteria pass. |
| 2026-06-23 16:15 CDT | Ran the full proof target and self-audit pass. | `python3 -m py_compile scripts/motion_reference/*.py`; `python3 scripts/motion_reference/test_report_motion_pipeline_gaps.py`; `python3 scripts/motion_reference/test_preflight_motion_data_factory.py`; `python3 scripts/motion_reference/report_motion_pipeline_gaps.py`; `python3 scripts/motion_reference/preflight_motion_data_factory.py`; `scripts/motion_reference/preflight_motion_data_factory.py`; `git diff --check`. | All proof commands exited 0. Existing gap report still shows 4 guide-ready and 11 reference-capture-required rows; new factory preflight exposes 15 tiered rows, 4 guide-ready, 0 validation-ready, and 11 guide blockers. No packaged `Sources/CamiFitApp/Resources/MotionDemos/*.jsonl` files changed. | Commit the completed executable slice locally on `agent/motion-data-factory-goal-loop` and report the hash. |

## Stop Conditions

- Objective complete:
  Done criteria pass and proof target commands are green.
- Blocked:
  The same missing external input, capture asset, credential, or unavailable tool blocks progress for three materially identical iterations.
- Owner decision needed:
  A product decision is required between multiple incompatible data-source strategies, licensing obligations, or promotion policy changes.
- Cost/risk threshold:
  Work would require downloading large datasets, committing large artifacts, altering guide-ready app motion files, or changing installed-app behavior without a separate approval.
