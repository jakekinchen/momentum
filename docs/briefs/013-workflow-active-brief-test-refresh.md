# Slice Brief 013 - Workflow Active Brief Test Refresh

**Date:** 2026-06-04

## Human Direction

The user said: "make sure the coding pair is running still, we need this
completed and tested before EOD".

Executor session log
`docs/session-logs/013-executor-eod-prd-acceptance-audit.md` found that product
P0 behavior appears covered, but broad `uv run pytest` is still red because
workflow tests expect the older
`docs/briefs/011-jordan-plyometric-knee-safety.md` active brief.

Reviewer decision `CONTINUE` in
`docs/reviewer-messages/013-review-eod-prd-acceptance-audit.md` accepted the
audit slice and selected this as the smallest remaining EOD testing blocker.

## Objective

Refresh the stale workflow-test expectations so the repo's workflow tests match
the current active brief and the broad pytest command can go green.

This slice should not make product-code, graph-seed, resolver, safety,
alternative, member-retrieval, ontology, or validation-runtime changes. It
should only repair stale workflow-state assertions and record validation
evidence.

## Product / Project Value

The PRD acceptance audit already maps the current implementation to the P0 demo
behaviors, but the EOD completion/testing milestone cannot stop while the full
test suite is red. Fixing the stale workflow expectations is the smallest
remaining step before a reviewer can make a repo-evidence-based `STOP`
decision.

## Acceptance Criteria

- Preserve deterministic graph behavior over LLM-driven eligibility.
- Do not use vector search for safety enforcement. Do not use embeddings,
  vector retrieval, or an LLM for safety enforcement.
- Do not claim ontology IDs, SNOMED codes, release IDs, access dates, or
  license status as verified unless `graph/ontology-lock.json` contains
  verified pinned values.
- Preserve `MAPS_TO` as ontology audit metadata only.
- Update only stale workflow-test expectations in
  `tests/test_workflow_scripts.py` that still expect
  `docs/briefs/011-jordan-plyometric-knee-safety.md`.
- The refreshed assertions must match the active brief in `GOAL.md`:
  `docs/briefs/013-workflow-active-brief-test-refresh.md`, or use a small
  test-local helper that derives the current active brief from `GOAL.md`.
- Do not modify workflow scripts unless the stale tests expose a real script
  bug that is proven by command output.
- Do not modify product modules under `kg/`, graph seed files under `graph/`,
  or PRD/product docs.
- `UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run pytest` must pass.
- `UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run python -m kg.validation`
  must pass and continue to report unverified ontology status rather than
  verified external ontology claims.
- `bash scripts/audit_autonomous_workflow.sh` and
  `node scripts/audit_codex_pair_state.mjs` must pass with the current active
  brief.
- Record whether the evidence now supports reviewer `STOP`, or identify exactly
  one remaining blocker with an evidence anchor.

## Expected Files

- `tests/test_workflow_scripts.py`
- `docs/session-logs/014-executor-workflow-active-brief-test-refresh.md`

No product code, graph seed, ontology lock, PRD, workflow script, or unrelated
docs changes are expected.

## Validation Commands

```bash
bash scripts/validate_resume_brief.sh docs/briefs/013-workflow-active-brief-test-refresh.md
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run pytest tests/test_workflow_scripts.py::test_agent_thread_status_reports_current_goal_state_and_audits tests/test_workflow_scripts.py::test_workflow_audit_requires_handoff_artifacts_and_stop_guard
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run pytest
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run python -m kg.validation
bash scripts/audit_autonomous_workflow.sh
node scripts/audit_codex_pair_state.mjs
git diff --check
```

## Evidence To Record

- Changed files.
- Exact stale assertions found and exact replacement behavior.
- Validation command output.
- Confirmation that product modules and graph seeds were not changed.
- Confirmation that deterministic graph behavior is preserved.
- Confirmation that no vector safety enforcement, LLM eligibility path, or
  unverified ontology claim was introduced.
- Explicit recommendation: reviewer `STOP` if full validation is green, or one
  evidence-backed remaining blocker if not.

## Reachability / Demo Proof

Record command-backed proof that:

- `bash scripts/agent_thread_status.sh` reports current slice
  `docs/briefs/013-workflow-active-brief-test-refresh.md`;
- `bash scripts/audit_autonomous_workflow.sh` reports active brief
  `docs/briefs/013-workflow-active-brief-test-refresh.md`;
- the focused workflow tests that previously failed now pass;
- full `uv run pytest` passes.

## Out Of Scope

- Product-code, graph-seed, resolver, safety, alternative, member-retrieval, or
  ontology validation changes.
- Creating external accounts, paid resources, or live ontology downloads.
- Verified ontology metadata, SNOMED/OPE/COPPER ID pinning, release IDs, access
  dates, or license claims.
- Vector retrieval, GraphRAG, embeddings, or LLM-generated safety decisions.
- New frontend, HTTP server, dashboard, or live API routing.
- Broad workflow redesign, manager protocol changes, or stop-sentinel policy
  changes.

## Stop Conditions

- The stale workflow-test expectations are refreshed, full validation is green,
  and the executor recommends reviewer `STOP`.
- The failures are not limited to stale workflow-test expectations and another
  concrete blocker is proven by command output.
- The slice would require changing product behavior, ontology truth claims, or
  safety policy.
- A human explicitly redirects the EOD completion/testing scope.

## Resume Checklist

- Human direction is recorded in this brief.
- Run `bash scripts/validate_resume_brief.sh docs/briefs/013-workflow-active-brief-test-refresh.md`.
- Confirm `GOAL.md` points at
  `docs/briefs/013-workflow-active-brief-test-refresh.md`.
- Confirm `<stop-orchestrator/>` is absent from `GOAL.md`.
- Run `bash scripts/agent_thread_status.sh`.
- Commit this brief, the reviewer message, `GOAL.md`, and scaffold matrix update
  with exact `git add` paths before starting an executor turn.
