# Slice Brief 001 - M0 KG Module Skeleton

**Date:** 2026-06-04

## Objective

Create the minimum FitGraph KG project skeleton that can support the PRD without
pretending the full graph behavior is already implemented.

## Product / Project Value

This gives the pair a runnable foundation: package metadata, module boundaries,
seed graph file locations, a health/validation path, and tests. Future slices
can add resolver, safety, alternatives, and Copilot behavior without arguing
about layout.

## Acceptance Criteria

- A Python package layout exists for the P0 modules named in the PRD.
- `graph/` contains seed-file placeholders for the PRD P0 files.
- `graph/ontology-lock.json` records placeholder metadata and clear TODO status
  for unverified ontology IDs.
- A basic health or validation function reports graph/ruleset/ontology versions
  and seed-file presence.
- Tests prove the package imports and the health/validation function works.
- The executor session log records exactly what was implemented and what remains
  PRD-pending.

## Expected Files

- `pyproject.toml`
- `kg/__init__.py`
- `kg/graph_store.py`
- `kg/ingest.py`
- `kg/resolver.py`
- `kg/constraints.py`
- `kg/safety.py`
- `kg/alternatives.py`
- `kg/provenance.py`
- `kg/member_retrieval.py`
- `kg/validation.py`
- `graph/exercise_kg.seed.json`
- `graph/member_kg.seed.json`
- `graph/ontology_mappings.seed.json`
- `graph/safety_rules.seed.json`
- `graph/provenance_schema.json`
- `graph/ontology-lock.json`
- `tests/`
- `docs/session-logs/001-executor-m0-kg-module-skeleton.md`

## Test Plan

- Prefer `uv run pytest` if `uv` is available.
- Otherwise use `python -m pytest`.
- If pytest is not installed, record the exact blocker and use import-level
  validation with the system Python.

## Validation Commands

```bash
python -m pytest
python -m kg.validation
```

## Evidence To Record

- Changed files.
- Validation command output.
- Any assumptions about Python version, package tooling, or unverified ontology
  metadata.
- PRD sections that remain unimplemented.

## Reachability / Demo Proof

At minimum, `python -m kg.validation` should read the seed graph directory and
print a deterministic health summary.

## Cross-Doc Impact

Update `GOAL.md` only if the current slice changes. Do not rewrite the PRD.

## Out Of Scope

- Full resolver behavior.
- Full safety traversal.
- Workout generation.
- Coach Copilot query routing.
- Live ontology downloads or external account setup.

## Stop Conditions

- The repo cannot support a Python package for a concrete reason.
- A human explicitly chooses another implementation stack.

