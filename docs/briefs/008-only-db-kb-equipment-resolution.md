# Slice Brief 008 - Only DB/KB Equipment Resolution

**Date:** 2026-06-04

## Objective

Implement the smallest deterministic golden-case slice for the PRD phrase
`only dumbbells and kettlebell`. The slice should prove that an equipment-subset
prompt can resolve to typed equipment constraints and drive hard equipment
filtering through the current safety and workout-candidate path.

## Product / Project Value

This closes a remaining EOD completion/testing gap in the Workout Generator
surface. It demonstrates that "only these tools" is enforced by the graph and
receipt pipeline rather than by LLM prose or vector retrieval.

## Acceptance Criteria

- Preserve deterministic graph behavior over LLM-driven eligibility.
- Do not use vector search for safety enforcement.
- Do not claim ontology IDs, SNOMED codes, release IDs, access dates, or
  license status as verified.
- Add or use local runtime graph equipment nodes and aliases needed for
  `dumbbell`, `dumbbells`, `db`, `kettlebell`, and `kb` without broad Jordan
  equipment expansion.
- Resolve `only dumbbells and kettlebell` into typed equipment availability or
  allowed-equipment constraints in a deterministic, testable shape.
- Prove the hard subset behavior with a golden test: exercises requiring
  equipment outside dumbbell/kettlebell are filtered with
  `EQUIPMENT_HARD_BLOCK`, while compatible exercises remain eligible unless
  another hard safety rule applies.
- Prove the workout-candidate result uses the already-safe pool for
  alternatives under the DB/KB subset.
- Keep `MAPS_TO` as ontology audit metadata only.
- Record any PRD-pending work that remains after this slice.

## Expected Files

- `kg/resolver.py`
- `kg/safety.py` only if the existing available-equipment path cannot express
  the subset contract cleanly
- `kg/alternatives.py` only if workout-candidate coverage needs a small API
  helper adjustment
- `graph/exercise_kg.seed.json`
- `tests/test_resolver.py`
- `tests/test_safety.py`
- `tests/test_alternatives.py`
- `docs/session-logs/008-executor-only-db-kb-equipment-resolution.md`

## Validation Commands

```bash
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run pytest tests/test_resolver.py tests/test_safety.py tests/test_alternatives.py
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run pytest
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run python -m kg.validation
bash scripts/audit_autonomous_workflow.sh
node scripts/audit_codex_pair_state.mjs
```

## Evidence To Record

- Changed files.
- Validation command output.
- Exact resolved constraints for `only dumbbells and kettlebell`.
- A receipt showing an incompatible-equipment exercise filtered with graph
  paths.
- A receipt showing a compatible exercise remains selected unless another hard
  rule applies.
- A workout-candidate result showing alternatives come from the selected safe
  pool.
- Confirmation that deterministic graph behavior is preserved.
- Confirmation that no vector search, LLM eligibility, or verified ontology
  claim was introduced.
- Remaining PRD-pending work, if any.

## Reachability / Demo Proof

At minimum, record direct command-backed examples for:

- `resolve_text("only dumbbells and kettlebell")`;
- `evaluate_candidates(..., available_equipment={"Equipment:dumbbell", "Equipment:kettlebell"}, ...)`;
- `build_workout_candidates(...)` under the same equipment subset.

## Out Of Scope

- Creating external accounts, paid resources, or live ontology downloads.
- Verified ontology metadata or SNOMED/OPE/COPPER ID pinning.
- Full Jordan equipment expansion beyond the minimal DB/KB golden case.
- New frontend, HTTP server, or live API routing.
- Replacing deterministic safety enforcement with LLM, embedding, or vector
  retrieval behavior.

## Stop Conditions

- The slice would require claiming unverified ontology metadata.
- The slice would replace deterministic graph safety enforcement.
- The DB/KB phrase cannot be represented without a product decision about how
  prompt-derived equipment availability should override member equipment.
- A human explicitly redirects the EOD completion/testing scope.
