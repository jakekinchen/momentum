# Slice Brief 004 - M3 Alternatives And Workout Candidate API

**Date:** 2026-06-04

## Objective

Implement the smallest alternatives/workout-candidate API that uses M2 safety
receipts as input and selects alternatives only from the already-safe exercise
pool.

## Product / Project Value

This slice should prove the PRD rule that alternatives never come from unsafe
or filtered exercises. It should expose a small contract that future workout
generation can call without letting an LLM decide eligibility.

## Acceptance Criteria

- Add tiny local graph facts needed for alternative scoring:
  - `Exercise -TARGETS-> MuscleGroup`
  - `Exercise -HAS_PATTERN-> MovementPattern`
  - enough muscle and movement-pattern nodes to compare the M2 candidate set.
- `kg.alternatives` selects alternatives only from receipts whose
  `decision == "selected"`.
- Alternative scoring uses the PRD weights where data exists:
  - target muscle overlap;
  - movement pattern similarity;
  - equipment preference;
  - priority tier.
- The API returns a deterministic structure for filtered candidates that
  includes:
  - filtered exercise ID;
  - selected alternative exercise ID;
  - derived-from relationship;
  - score or score components;
  - graph paths explaining why the alternative is safe and relevant.
- Add a minimal workout-candidate function that returns selected receipts,
  filtered receipts, and alternative records from the same safety result set.
- Tests prove:
  - alternatives are chosen from selected receipts only;
  - a filtered unsafe exercise is never used as an alternative;
  - a safe lower-impact candidate can be selected as an alternative for a
    filtered knee-stressing candidate;
  - no alternative is returned when the safe pool is empty;
  - output ordering is deterministic.
- The executor session log records exactly what was implemented and what remains
  PRD-pending.

## Expected Files

- `kg/alternatives.py`
- `kg/graph_store.py`
- `graph/exercise_kg.seed.json`
- `tests/test_alternatives.py`
- `docs/session-logs/004-executor-m3-alternatives-workout-candidates.md`

## Test Plan

- Prefer `uv run pytest`.
- Run `uv run python -m kg.validation` after seed changes.
- Include tests that use real M2 `DecisionReceipt` objects rather than manually
  trusting unsafe candidates.

## Validation Commands

```bash
uv run pytest
uv run python -m kg.validation
```

## Evidence To Record

- Changed files.
- Validation command output.
- Example safety receipts and resulting alternative records.
- Proof that alternatives came from selected receipts only.
- PRD sections that remain unimplemented.

## Reachability / Demo Proof

At minimum, a deterministic call should prove:

- `Exercise:goblet_squat` is filtered under active knee restriction.
- `Exercise:glute_bridge` is selected.
- the alternative record for `Exercise:goblet_squat` points to
  `Exercise:glute_bridge`.
- no filtered exercise appears in the safe alternative pool.

## Cross-Doc Impact

Do not rewrite the PRD. Update `GOAL.md` only if the current slice changes
again.

## Out Of Scope

- Full workout plan generation.
- Coach Copilot retrieval.
- Member adherence/churn context.
- Fuzzy resolver expansion.
- Embedding fallback.
- Live ontology downloads or pinned SNOMED/OPE/COPPER IDs.

## Stop Conditions

- Alternatives would require using unsafe or filtered candidates.
- Alternative scoring would require unverifiable ontology claims.
- A human explicitly chooses another implementation stack.
