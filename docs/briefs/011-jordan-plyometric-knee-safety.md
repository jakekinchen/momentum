# Slice Brief 011 - Jordan Plyometric Knee Safety Coverage

**Date:** 2026-06-04

## Human Direction

The user said: "make sure the coding pair is running still, we need this
completed and tested before EOD".

Reviewer decision `CONTINUE` in
`docs/reviewer-messages/011-review-bad-lower-back-resolver-safety.md` accepted
the lower-back resolver/safety slice and selected this as the next smallest
remaining PRD-bound EOD completion/testing gap.

## Objective

Close the remaining P0 safety proof that Jordan's active knee restriction
removes plyometric or high-impact jumping exercises.

The slice should add the minimal local runtime graph facts, deterministic safety
rule behavior, and tests needed to prove a high-impact plyometric knee-stressing
exercise is filtered by a `MEDICAL_HARD_BLOCK` receipt while at least one
non-plyometric available exercise remains selected.

## Product / Project Value

The PRD says Jordan's knee restriction should remove plyometrics and high-impact
jumping, not just deep loaded knee flexion. This slice closes that concrete P0
demo/testing gap without broad clinical modeling or non-deterministic safety
logic.

## Acceptance Criteria

- Preserve deterministic graph behavior over LLM-driven eligibility.
- Do not use vector search, embeddings, vector retrieval, or an LLM for safety
  enforcement.
- Do not claim ontology IDs, SNOMED codes, release IDs, access dates, or
  license status as verified unless `graph/ontology-lock.json` contains
  verified pinned values.
- Preserve `MAPS_TO` as ontology audit metadata only.
- Add only local unverified runtime graph data for the minimal
  plyometric/high-impact jumping candidate needed by the PRD proof.
- Add or reuse a local deterministic safety rule so an active hard knee
  restriction filters the plyometric/high-impact exercise through graph paths
  and rule paths.
- The filtered exercise receipt must have `decision="filtered"`,
  `primary_severity="MEDICAL_HARD_BLOCK"`, and a clear reason code for the
  high-impact knee restriction.
- The receipt graph paths must include the exercise stress or pattern evidence,
  any relevant local `PART_OF` closure path, and the local safety rule path.
- The same hard knee restriction must not ban every available exercise; at least
  one non-plyometric existing exercise should remain selected when equipment is
  available.
- Existing resolver, lower-back, equipment, deadlift, alternatives, Copilot
  fact-card, workflow, and validation tests must continue to pass.
- Record remaining PRD-pending work after this slice.

## Expected Files

- `graph/exercise_kg.seed.json`
- `graph/safety_rules.seed.json`
- `kg/safety.py` only if the current safety rule matcher cannot express the
  deterministic high-impact proof.
- `tests/test_safety.py`
- `tests/test_alternatives.py` only if workout-candidate or alternative proof
  needs a focused assertion.
- `docs/session-logs/012-executor-jordan-plyometric-knee-safety.md`

## Validation Commands

```bash
bash scripts/validate_resume_brief.sh docs/briefs/011-jordan-plyometric-knee-safety.md
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run pytest tests/test_safety.py tests/test_alternatives.py
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run pytest
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run python -m kg.validation
bash scripts/audit_autonomous_workflow.sh
node scripts/audit_codex_pair_state.mjs
```

## Evidence To Record

- Changed files.
- Validation command output.
- Exact safety receipt for the plyometric/high-impact exercise under Jordan's
  active hard knee restriction.
- Exact safety receipt for at least one non-plyometric available exercise that
  remains selected under the same restriction.
- Confirmation that deterministic graph behavior is preserved.
- Confirmation that no vector safety enforcement, LLM eligibility, or
  unverified ontology claim was introduced.
- Remaining PRD-pending work, if any.

## Reachability / Demo Proof

At minimum, record a direct command-backed `evaluate_candidates(...)` example
under the active hard knee restriction that shows:

- the plyometric/high-impact candidate is filtered with a medical hard block;
- the receipt includes graph/rule paths that justify the block;
- an available non-plyometric candidate remains selected.

## Out Of Scope

- Creating external accounts, paid resources, or live ontology downloads.
- Verified ontology metadata, SNOMED/OPE/COPPER ID pinning, release IDs, access
  dates, or license claims.
- Vector retrieval, GraphRAG, embeddings, or LLM-generated safety decisions.
- Broad clinical modeling beyond the minimal local unverified graph needed for
  the PRD high-impact jumping proof.
- New frontend, HTTP server, dashboard, or live API routing.
- Replacing deterministic safety enforcement with LLM, embedding, or vector
  retrieval behavior.

## Stop Conditions

- The slice would require a clinical or ontology decision that cannot be
  represented as local unverified seed data.
- The slice would require claiming unverified ontology metadata.
- The slice would replace deterministic safety enforcement with LLM, embedding,
  or vector retrieval behavior.
- A human explicitly redirects the EOD completion/testing scope.

## Resume Checklist

- Human direction is recorded in this brief.
- Run `bash scripts/validate_resume_brief.sh docs/briefs/011-jordan-plyometric-knee-safety.md`.
- Confirm `GOAL.md` points at
  `docs/briefs/011-jordan-plyometric-knee-safety.md`.
- Confirm `<stop-orchestrator/>` is absent from `GOAL.md`.
- Run `bash scripts/agent_thread_status.sh`.
- Commit this brief and `GOAL.md` update with exact `git add` paths before
  starting an executor turn.
