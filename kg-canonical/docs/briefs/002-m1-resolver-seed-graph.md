# Slice Brief 002 - M1 Resolver And Seed Graph

**Date:** 2026-06-04

## Objective

Implement the smallest useful M1 seed graph and resolver behavior that proves
local typed graph traversal can support resolver output without pretending full
safety evaluation is done.

## Product / Project Value

This slice gives the pair real, testable graph facts for the PRD's first proof
points: `knee` anatomy closure, `left knee` laterality, `kettlebell` equipment
resolution, `no barbell` negated equipment resolution, and `exclude deadlifts`
exercise-family resolution. Future safety slices can consume these typed
constraints and graph paths directly.

## Acceptance Criteria

- `graph/exercise_kg.seed.json` contains a tiny local taxonomy with typed nodes
  for:
  - `BodyRegion:knee`
  - at least three knee substructures such as `left_knee`, `knee_joint`, and
    `patella`
  - `Equipment:Kettlebell`
  - `Equipment:Barbell`
  - `ExerciseFamily:DeadliftFamily`
- `graph/exercise_kg.seed.json` contains local runtime edges for knee
  `PART_OF` closure.
- `graph/ontology_mappings.seed.json` may add placeholder `LocalTerm` and
  `MAPS_TO` records, but any ontology concept IDs must remain unverified unless
  they are pinned in `graph/ontology-lock.json`.
- `kg.graph_store` exposes enough typed graph loading or traversal behavior to
  support deterministic anatomy closure from seed files.
- `kg.resolver.resolve_text` returns typed `ResolvedConstraint` values for:
  - `knee`
  - `left knee`
  - `kettlebell`
  - `no barbell`
  - `exclude deadlifts`
- Unknown or ambiguous safety-relevant terms produce an unresolved typed
  constraint or unresolved concept representation. Do not silently ignore them.
- Tests prove resolver output, knee closure, and the separation between local
  safety graph edges and `MAPS_TO` ontology grounding.
- The executor session log records exactly what was implemented and what remains
  PRD-pending.

## Expected Files

- `kg/graph_store.py`
- `kg/ingest.py`
- `kg/resolver.py`
- `kg/constraints.py`
- `graph/exercise_kg.seed.json`
- `graph/ontology_mappings.seed.json`
- `graph/ontology-lock.json` only if metadata status wording must be tightened
- `tests/test_graph_store.py`
- `tests/test_resolver.py`
- `docs/session-logs/002-executor-m1-resolver-seed-graph.md`

## Test Plan

- Prefer `uv run pytest`.
- Run `uv run python -m kg.validation` after seed changes.
- If adding new CLI reachability for resolver behavior, record that command and
  output in the session log.

## Validation Commands

```bash
uv run pytest
uv run python -m kg.validation
```

## Evidence To Record

- Changed files.
- Validation command output.
- Resolver examples and returned typed constraints.
- Graph paths proving `knee` closure includes local knee substructures.
- Confirmation that ontology IDs remain unverified unless
  `graph/ontology-lock.json` pins verified values.
- PRD sections that remain unimplemented.

## Reachability / Demo Proof

At minimum, tests should prove:

- `resolve_text("knee")` returns a `BodyRegion:knee` constraint with closure
  paths to knee substructures.
- `resolve_text("left knee")` preserves laterality.
- `resolve_text("kettlebell")` returns an equipment constraint.
- `resolve_text("no barbell")` returns a negated equipment constraint.
- `resolve_text("exclude deadlifts")` returns a hard exercise-family exclusion.

## Cross-Doc Impact

Do not rewrite the PRD. Update `GOAL.md` only if the current slice changes
again.

## Out Of Scope

- Full fuzzy matching.
- Embedding fallback.
- Exercise eligibility or safety filtering.
- Decision receipts beyond resolver/graph-path evidence.
- Alternative selection.
- Workout generation.
- Coach Copilot retrieval.
- Live ontology downloads or external account setup.

## Stop Conditions

- The current seed format cannot support deterministic local graph traversal for
  a concrete reason.
- A human explicitly chooses another implementation stack.
- Resolver behavior would require claiming unverified ontology IDs as pinned.
