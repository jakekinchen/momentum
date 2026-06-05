# Human-Approved Resume Brief

**Date:** 2026-06-04

## Human Direction

The user said: "make sure the coding pair is running still, we need this
completed and tested before EOD".

This is fresh human direction to resume the coding pair for an EOD completion
and testing pass.

## Objective

Run the smallest useful EOD completion and testing slice for the FitGraph KG
module. Verify the current implementation against `docs/kg-module-prd.md`,
close any small test or evidence gaps that block a defensible completion claim,
and record concrete validation evidence for the reviewer.

## Product / Project Value

This slice turns the stopped post-M5 state into a final tested readiness pass
without overriding deterministic graph behavior. It gives the executor/reviewer
pair a bounded lane to prove what is complete, identify any remaining
PRD-pending work, and avoid drifting into broad unrequested product changes.

## Acceptance Criteria

- Preserve deterministic graph behavior over LLM-driven eligibility.
- Preserve `MAPS_TO` as ontology audit metadata unless a verified ontology
  value is already pinned in `graph/ontology-lock.json`.
- Do not claim ontology IDs, SNOMED codes, release IDs, access dates, or license
  status are verified unless `graph/ontology-lock.json` contains verified
  pinned values.
- Do not use vector search for safety enforcement.
- Run and record the full current test and validation set.
- Check the implemented KG module against `docs/kg-module-prd.md` at the scope
  needed for an EOD completion/testing claim.
- If a small deterministic test or evidence gap blocks completion, fix it in
  the smallest reviewable change and record the changed files.
- If completion is already supported by current evidence, write the executor
  session log with the evidence and leave the reviewer to record the final
  decision.

## Expected Files

- `GOAL.md`
- `docs/briefs/007-eod-completion-testing.md`
- `docs/session-logs/NNN-executor-*.md`
- `docs/reviewer-messages/NNN-review-*.md`
- Focused code, graph, or test files only if the EOD audit finds a concrete
  completion/testing gap.

## Validation Commands

```bash
bash scripts/validate_resume_brief.sh docs/briefs/007-eod-completion-testing.md
uv run pytest
uv run python -m kg.validation
bash scripts/audit_autonomous_workflow.sh
node scripts/audit_codex_pair_state.mjs
```

## Evidence To Record

- Changed files.
- Validation command output.
- PRD acceptance evidence reviewed for the EOD completion/testing claim.
- Confirmation that deterministic graph behavior is preserved.
- Confirmation that vector search is not used for safety enforcement.
- Explicit confirmation that no unverified ontology claims were introduced.
- Remaining PRD-pending work, if any.

## Reachability / Demo Proof

Run the full validation command set and record any direct module/API/test path
that proves the completion claim or the remaining blocker.

## Out Of Scope

- Creating external accounts, paid resources, or live ontology downloads.
- Claiming verified ontology metadata that is not pinned in
  `graph/ontology-lock.json`.
- Replacing deterministic safety enforcement with LLM, embedding, or vector
  retrieval behavior.
- Broad new product behavior beyond closing a concrete EOD completion/testing
  gap.

## Stop Conditions

- The reviewer records `STOP` because the EOD completion/testing evidence is
  sufficient.
- The reviewer records `ESCALATE` because a product, clinical, ontology, stack,
  or timing decision requires human input.
- The slice would require claiming unverified ontology metadata.
- The slice would replace deterministic safety enforcement with LLM, embedding,
  or vector retrieval behavior.

## Resume Checklist

Before an executor starts:

- Human direction is recorded in this brief.
- Run `bash scripts/validate_resume_brief.sh docs/briefs/007-eod-completion-testing.md`.
- Update `GOAL.md` to point at `docs/briefs/007-eod-completion-testing.md`.
- Remove or intentionally replace `<stop-orchestrator/>` in `GOAL.md`.
- Run `bash scripts/agent_thread_status.sh`.
- Commit this brief and `GOAL.md` update with exact `git add` paths.
