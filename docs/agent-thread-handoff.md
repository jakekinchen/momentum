# FitGraph Agent Thread Handoff

Last updated: 2026-06-04T19:15:05Z

## Current State

- Branch: `main`
- M5 product commit: `4d23580 feat: add m5 ontology validation sidecar`
- M5 stop/reviewer commit:
  `5af36ff chore: review m5 and stop autonomous loop`
- `GOAL.md` contains `<stop-orchestrator/>`.
- Latest executor log:
  `docs/session-logs/006-executor-m5-ontology-sidecar-validation.md`
- Latest reviewer decision:
  `docs/reviewer-messages/006-review-m5-ontology-sidecar-validation.md`
- Reviewer decision: `STOP`

The M0-M5 autonomous plan has been completed and stopped. Do not start another
executor product slice while the stop sentinel is present.

## Start Here

1. Read `README.md` for the repo-level entrypoint.
2. Read `AGENTS.md`; it points future threads to this status/handoff flow.
3. Read `GOAL.md` and respect the stop sentinel.
4. Read `docs/reviewer-messages/006-review-m5-ontology-sidecar-validation.md`.
5. Run the one-command agent status check:

```bash
bash scripts/agent_thread_status.sh
```

The status script prints this handoff pointer, git state, stop-sentinel state,
neutral resume-planning guidance, a placeholder resume-validation command, the
workflow audit, and the Codex pair-state audit, then exits with a clean or
warning summary. Exact resume paths come from the resume planner after a
concrete human-approved slug is supplied.

The workflow audit should report the handoff/status scripts as required
workflow artifacts and should confirm the loop-start stop guard while
`<stop-orchestrator/>` is present.

You can also run the underlying audits directly:

```bash
git status --short --branch
bash scripts/audit_autonomous_workflow.sh
node scripts/audit_codex_pair_state.mjs
bash scripts/plan_next_resume_brief.sh
```

After drafting a candidate resume brief, validate that specific file before
changing `GOAL.md`. Use the `next brief:` path printed by the planner:

```bash
bash scripts/validate_resume_brief.sh <planner-next-brief-path>
```

## Safe Checks

These commands are safe orientation checks for future threads:

```bash
uv run pytest
uv run python -m kg.validation
```

Expected current validation shape:

- `uv run pytest` collected 61 tests and passed.
- `uv run python -m kg.validation` reports:
  - `validation_status: pass`
  - `schema_validation_status: pass`
  - `ontology_status: todo_unverified`
  - `verified: false`
  - `ontology_sidecar_export_status: available_unverified`

The pytest suite includes workflow-script coverage for the agent status command,
the `README.md` and `AGENTS.md` handoff pointers, the workflow audit's handoff
checks, the resume brief template, the resume planner and validator, and the
loop-start stop guard. The workflow audit exits non-zero when required
artifacts are missing or when either `README.md` or `AGENTS.md` loses the
agent-status, handoff, stop-sentinel, or resume-validation entrypoint guidance.
It also verifies that `scripts/agent_thread_status.sh` keeps neutral stopped
resume guidance and avoids stale concrete resume-validation targets.
The workflow audit verifies that the Manager protocol preserves stopped-state
support boundaries and durable manager-log guidance.
It also verifies that `docs/manager-log/000-template-manager-support.md` exists
and keeps the required stopped-state manager log sections.
Resume-brief validation rejects vector safety enforcement language. The
workflow audit also verifies that the active brief named in `GOAL.md` exists.
The agent status command intentionally keeps stopped-state resume validation
neutral with `<planner-next-brief-path>`. The resume planner prints the
candidate `validate_resume_brief.sh` command once a concrete slug is supplied,
and candidate resume briefs must carry that self-validation command before the
`GOAL.md` update. The resume validator also requires that command to target the
candidate brief being validated, not a stale copied path, and the exact command
must appear in the brief's `## Resume Checklist`. Static orientation docs use
`<planner-next-brief-path>` and the workflow audit rejects stale hardcoded
`007` resume-validation targets. No-slug planner output does not print
command-shaped placeholder `GOAL.md` or `git add` paths; rerun the planner with
a concrete slug before using exact paths.

## Hard Invariants

- Runtime safety uses deterministic local graph traversal.
- Member safety and equipment constraints are hard blocks.
- Member dislikes are soft constraints unless explicitly configured as hard
  blocks.
- `MAPS_TO` is ontology audit metadata, not a runtime safety edge.
- Vector search must not enforce safety.
- Do not claim ontology IDs, SNOMED codes, release IDs, access dates, or
  license status are verified unless `graph/ontology-lock.json` contains the
  verified pinned values.

## Resume Rules

A future thread should resume product work only after fresh human direction. A
safe resume should:

- remove or intentionally replace `<stop-orchestrator/>` in `GOAL.md`;
- copy `docs/briefs/000-template-human-approved-resume.md` into a new numbered
  active brief under `docs/briefs/`;
- use `bash scripts/plan_next_resume_brief.sh verified-ontology-lock` with a
  slug matching the human-approved slice to preview the next brief path and
  exact copy command before changing files;
- run `bash scripts/validate_resume_brief.sh <planner-next-brief-path>` on the
  drafted brief before pointing `GOAL.md` at it;
- update `GOAL.md` to point at that brief;
- preserve the source-of-truth order in `AGENTS.md`;
- leave a session log for executor work or a reviewer decision for review work;
- commit with exact `git add` paths.

Good next human-approved brief themes include:

- verified ontology lockfile process using supplied source data;
- production RDF/Turtle export and SHACL validation;
- richer exercise and member graph coverage;
- Coach Copilot integration constrained to graph-backed fact cards;
- production API boundaries for recommendation runs and decision receipts.

## What Not To Do

- Do not run `scripts/run_codex_pair_cycle.sh --once` while the stop sentinel is
  present.
- Do not start `scripts/start_codex_goal_loop.sh` while the stop sentinel is
  present. The start script should refuse with a stop-sentinel message.
- Do not pin external ontology IDs from memory or unstated assumptions.
- Do not replace deterministic safety checks with LLM, embedding, or vector
  retrieval behavior.
