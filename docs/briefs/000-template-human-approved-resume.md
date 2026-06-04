# Slice Brief Template - Human-Approved Resume

**Date:** YYYY-MM-DD

## Human Direction

Replace this section with the exact human instruction that authorizes resuming
product work. A fresh human direction must exist before this template becomes an
active brief and `GOAL.md` is intentionally updated.

## Objective

Describe the smallest useful product or process slice to implement.

## Product / Project Value

Explain why this slice matters and how it moves FitGraph toward the PRD without
overriding deterministic graph behavior.

## Acceptance Criteria

- Keep acceptance criteria concrete and testable.
- Preserve deterministic graph behavior over LLM-driven eligibility.
- Preserve `MAPS_TO` as ontology audit metadata unless the human-approved brief
  explicitly changes the ontology path with verified source data.
- Do not claim ontology IDs, SNOMED codes, release IDs, access dates, or license
  status are verified unless `graph/ontology-lock.json` contains verified
  pinned values.

## Expected Files

- List exact files expected to change.
- Keep the slice small enough for one executor turn.

## Validation Commands

```bash
uv run pytest
uv run python -m kg.validation
bash scripts/audit_autonomous_workflow.sh
node scripts/audit_codex_pair_state.mjs
```

## Evidence To Record

- Changed files.
- Validation command output.
- Reachability or demo proof.
- Explicit confirmation that no unverified ontology claims were introduced.
- Remaining PRD-pending work.

## Reachability / Demo Proof

Name the command, API, test, or demo path that proves the slice is reachable.

## Out Of Scope

- List work that must not be done in this slice.
- Keep broad production hardening, ontology verification, or new product
  behavior out of scope unless the human instruction explicitly asks for it.

## Stop Conditions

- Human direction is missing or ambiguous.
- The slice would require claiming unverified ontology metadata.
- The slice would replace deterministic safety enforcement with LLM, embedding,
  or vector retrieval behavior.
- A product, clinical, ontology, or stack decision requires human approval.

## Resume Checklist

Before an executor starts:

- Remove or intentionally replace `<stop-orchestrator/>` in `GOAL.md`.
- Run `bash scripts/plan_next_resume_brief.sh`, then rerun it with the
  human-approved lowercase slice slug.
- Copy this template into the exact `next brief:` path printed by the planner.
- Run `bash scripts/validate_resume_brief.sh <planner-next-brief-path>` on the
  drafted brief before updating `GOAL.md`; replace `<planner-next-brief-path>`
  with the exact path printed by the planner.
- Update `GOAL.md` to point at the new active brief.
- Run `bash scripts/agent_thread_status.sh`.
- Commit the brief and `GOAL.md` update with exact `git add` paths.
