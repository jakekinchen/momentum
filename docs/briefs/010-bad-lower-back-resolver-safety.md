# Slice Brief 010 - Bad Lower Back Resolver And Safety Coverage

**Date:** 2026-06-04

## Human Direction

The user said: "make sure the coding pair is running still, we need this
completed and tested before EOD".

Reviewer decision `CONTINUE` in
`docs/reviewer-messages/010-review-copilot-sleep-churn-coach-brief-fact-cards.md`
accepted the Copilot P0 fact-card slice and selected this as the next smallest
PRD-bound EOD completion/testing slice.

## Objective

Close the remaining PRD resolver/safety golden gap for `bad lower back`.

The slice should extend the local runtime graph and deterministic resolver so
`bad lower back` resolves to a local low-back or lumbar-spine body-region
constraint, then prove that a hard lower-back restriction blocks only exercises
whose local graph stress paths and safety rules justify the block.

## Product / Project Value

The PRD requires `bad lower back` as a resolver example and requires safety
decisions to be graph-driven rather than LLM-improvised. This slice turns that
remaining prompt example into deterministic graph behavior with tests and
receipt paths, improving stop-readiness for the EOD completion/testing mission.

## Acceptance Criteria

- Preserve deterministic graph behavior over LLM-driven eligibility.
- Do not use vector search for safety enforcement.
- Do not use vector retrieval, embeddings, or an LLM to decide lower-back
  safety.
- Do not claim ontology IDs, SNOMED codes, release IDs, access dates, or
  license status as verified unless `graph/ontology-lock.json` contains
  verified pinned values.
- Preserve `MAPS_TO` as ontology audit metadata only.
- Add local unverified runtime graph nodes for the minimal low-back/lumbar
  concept shape needed by the `bad lower back` example.
- Add local runtime graph stress data for at least one exercise that should be
  blocked by a hard lower-back restriction.
- Add a local deterministic safety rule, or reuse an existing rule if it already
  fits, so the block is justified by graph paths and rule paths.
- `resolve_text("bad lower back")` must return a typed safety-critical
  constraint for the local lower-back/lumbar concept rather than an unresolved
  concept.
- Safety evaluation under that hard lower-back restriction must filter the
  lower-back-stressing exercise with a `MEDICAL_HARD_BLOCK` receipt and source
  graph paths.
- Safety evaluation must not ban every exercise merely because the prompt says
  `bad lower back`; at least one non-lower-back-stressing existing exercise
  should remain selected when equipment is available.
- Existing knee, equipment, deadlift, alternatives, and Copilot fact-card tests
  must continue to pass.
- Record remaining PRD-pending work after this slice.

## Expected Files

- `graph/exercise_kg.seed.json`
- `graph/safety_rules.seed.json`
- `kg/resolver.py`
- `tests/test_resolver.py`
- `tests/test_safety.py`
- `tests/test_alternatives.py` only if workout-candidate or alternative proof
  needs a focused assertion
- `docs/session-logs/011-executor-bad-lower-back-resolver-safety.md`

## Validation Commands

```bash
bash scripts/validate_resume_brief.sh docs/briefs/010-bad-lower-back-resolver-safety.md
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run pytest tests/test_resolver.py tests/test_safety.py tests/test_alternatives.py
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run pytest
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run python -m kg.validation
bash scripts/audit_autonomous_workflow.sh
node scripts/audit_codex_pair_state.mjs
```

## Evidence To Record

- Changed files.
- Validation command output.
- Exact `resolve_text("bad lower back")` output, including constraint type,
  value, `hard`, `safety_behavior`, and graph paths.
- Exact safety receipt for the lower-back-stressing exercise under the hard
  lower-back restriction.
- Exact safety receipt for at least one exercise that remains selected under
  the same restriction.
- Confirmation that deterministic graph behavior is preserved.
- Confirmation that no vector safety enforcement, LLM eligibility, or
  unverified ontology claim was introduced.
- Remaining PRD-pending work, if any.

## Reachability / Demo Proof

At minimum, record direct command-backed examples for:

- `resolve_text("bad lower back")`;
- `evaluate_candidates(...)` under the resolved hard lower-back restriction for
  one blocked lower-back-stressing exercise;
- `evaluate_candidates(...)` under the same restriction for one selected
  exercise whose graph stress paths do not hit the lower-back rule.

## Out Of Scope

- Creating external accounts, paid resources, or live ontology downloads.
- Verified ontology metadata, SNOMED/OPE/COPPER ID pinning, release IDs, access
  dates, or license claims.
- Vector retrieval, GraphRAG, embeddings, or LLM-generated safety decisions.
- Broad clinical modeling beyond the minimal local unverified lower-back graph
  needed for the PRD example.
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
- Run `bash scripts/validate_resume_brief.sh docs/briefs/010-bad-lower-back-resolver-safety.md`.
- Confirm `GOAL.md` points at
  `docs/briefs/010-bad-lower-back-resolver-safety.md`.
- Confirm `<stop-orchestrator/>` is absent from `GOAL.md`.
- Run `bash scripts/agent_thread_status.sh`.
- Commit this brief and `GOAL.md` update with exact `git add` paths before
  starting an executor turn.
