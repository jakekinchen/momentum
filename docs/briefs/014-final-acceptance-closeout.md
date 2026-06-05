# Slice Brief 014 - Final Acceptance Closeout

**Date:** 2026-06-04

## Human Direction

The user said: "push it to 100%, use subagents".

This is fresh human direction to resume from the stopped EOD state, remove the
stop sentinel, and finish the remaining acceptance blockers with parallel
subagent support.

## Objective

Close the remaining FitGraph EOD acceptance gaps so the repo has green broad
validation and command-backed proof for the PRD-style full workout prompt:

`Build a 50-minute lower-body session. Exclude deadlifts. Only DB and KB.`

## Product / Project Value

The previous reviewer `STOP` established strong P0 product coverage, but a
live manager check found broad workflow tests still failed after the stop
sentinel was added, and the full PRD-style prompt still resolved as a single
`UnresolvedConcept`. This slice turns that last-mile evidence into a complete,
reviewable closeout.

## Acceptance Criteria

- Preserve deterministic graph behavior over LLM-driven eligibility.
- Do not use vector search for safety enforcement. Do not use embedding
  retrieval, GraphRAG, or LLM eligibility for safety enforcement.
- Do not claim ontology IDs, SNOMED codes, release IDs, access dates, or
  license status are verified unless `graph/ontology-lock.json` contains
  verified pinned values.
- Refresh workflow tests so the stopped and resumed states are both handled
  intentionally instead of hardcoding the pre-stop sentinel state.
- Add deterministic full-prompt parsing or orchestration so the PRD-style
  workout prompt yields typed constraints for deadlift exclusion and DB/KB
  equipment subset rather than one unresolved concept.
- Prove the full prompt drives safety and workout-candidate behavior:
  deadlift variations are filtered, incompatible equipment is filtered, and
  alternatives come from the already-safe DB/KB pool.
- Preserve `MAPS_TO` as ontology audit metadata only.
- Use subagents for non-overlapping investigation or implementation lanes and
  integrate their results carefully.
- Leave command-backed evidence that broad pytest, KG validation, workflow
  audit, pair-state audit, and diff check pass.

## Expected Files

- `GOAL.md`
- `docs/briefs/014-final-acceptance-closeout.md`
- `graph/exercise_kg.seed.json` if a realistic lower-body equipment fixture is
  needed for full-prompt proof
- `tests/test_workflow_scripts.py`
- `kg/resolver.py` or a narrowly scoped orchestration helper if needed
- `kg/alternatives.py` or `kg/safety.py` only if full-prompt coverage cannot be
  expressed through the existing APIs
- `tests/test_resolver.py`
- `tests/test_safety.py` or `tests/test_alternatives.py`
- `docs/session-logs/015-executor-final-acceptance-closeout.md`
- `docs/reviewer-messages/015-review-final-acceptance-closeout.md`

## Validation Commands

```bash
bash scripts/validate_resume_brief.sh docs/briefs/014-final-acceptance-closeout.md
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run pytest
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run python -m kg.validation
bash scripts/audit_autonomous_workflow.sh
node scripts/audit_codex_pair_state.mjs
git diff --check
```

## Evidence To Record

- Changed files.
- Subagent assignments and conclusions.
- Validation command output.
- Direct proof for `resolve_text("Build a 50-minute lower-body session. Exclude deadlifts. Only DB and KB.")`.
- A receipt showing deadlift-family filtering under the full prompt.
- A receipt showing incompatible-equipment filtering under the full prompt.
- A workout-candidate result showing alternatives come from the selected safe
  DB/KB pool.
- Explicit confirmation that deterministic graph behavior is preserved.
- Explicit confirmation that no vector search, LLM eligibility, or verified
  ontology claim was introduced.
- Remaining PRD-pending work, if any.

## Reachability / Demo Proof

At minimum, record a direct Python command that imports the real modules and
proves the full prompt resolves to typed constraints, then passes those
constraints through `evaluate_candidates(...)` and
`build_workout_candidates(...)`.

## Out Of Scope

- External accounts, paid resources, or live ontology downloads.
- Verified ontology metadata or SNOMED/OPE/COPPER ID pinning.
- Frontend, HTTP server, dashboard, or live API routing.
- Broad member-context ingestion beyond the committed P0 fact cards.
- Replacing deterministic graph safety with LLM, embedding, vector, or
  GraphRAG behavior.

## Stop Conditions

- The slice would require claiming unverified ontology metadata.
- The slice would replace deterministic graph safety enforcement.
- The full PRD prompt cannot be represented without a product decision about
  phrase extraction versus typed resolver scope.
- A human explicitly redirects the final closeout scope.

## Resume Checklist

- Human direction is recorded in this brief.
- Run `bash scripts/validate_resume_brief.sh docs/briefs/014-final-acceptance-closeout.md`.
- Confirm `GOAL.md` points at
  `docs/briefs/014-final-acceptance-closeout.md`.
- Confirm `<stop-orchestrator/>` is absent from `GOAL.md`.
- Run `bash scripts/agent_thread_status.sh`.
- Commit this brief and `GOAL.md` update with exact `git add` paths before
  starting an executor turn, unless this thread is acting as the executor and
  records the combined closeout in the session log.
