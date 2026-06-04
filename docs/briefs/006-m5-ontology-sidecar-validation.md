# Slice Brief 006 - M5 Ontology Sidecar And Validation

**Date:** 2026-06-04

## Objective

Implement the smallest ontology-sidecar validation slice that tightens schema
checks for local graph seeds, SKOS-style mappings, PROV-shaped receipts, and
the ontology lockfile without claiming external ontology IDs are verified.

## Product / Project Value

This slice should preserve the production semantic-web path while keeping the
runtime local taxonomy authoritative. It should make false ontology claims
harder by validating the unverified lockfile state and checking that mappings
remain audit metadata rather than safety traversal edges.

## Acceptance Criteria

- Add validation helpers that check:
  - required seed files parse as JSON objects;
  - graph seed nodes have `id`, `type`, `label`, and unique IDs;
  - graph seed edges have valid `source`, `predicate`, and `target` references;
  - `ontology_mappings.seed.json` mapping records have local term IDs,
    ontology concept IDs, SKOS predicate, method, review status, and provenance
    source fields;
  - `MAPS_TO` is not treated as a runtime safety edge;
  - `graph/ontology-lock.json` remains explicitly unverified unless verified
    concept IDs are actually present.
- Add a minimal PROV-shaped receipt validation helper for `DecisionReceipt`.
- Add optional RDF/Turtle export scaffolding or a deterministic text export that
  clearly marks ontology concepts as unverified.
- `python -m kg.validation` should include validation findings for seed schema
  checks while still preserving the current pass/fail contract.
- Tests prove:
  - current graph and mapping seeds pass validation;
  - invalid edge references fail validation;
  - duplicate node IDs fail validation;
  - ontology lockfile cannot report verified without pinned values;
  - decision receipts satisfy the minimal PROV-shaped required fields.
- The executor session log records exactly what was implemented and what remains
  PRD-pending.

## Expected Files

- `kg/validation.py`
- `kg/provenance.py`
- `graph/provenance_schema.json` only if schema wording must be tightened
- `tests/test_validation.py`
- `tests/test_provenance.py` if receipt validation is split out
- `docs/session-logs/006-executor-m5-ontology-sidecar-validation.md`

## Test Plan

- Prefer `uv run pytest`.
- Run `uv run python -m kg.validation`.
- Include focused tests for invalid local graph seeds and lockfile truth.

## Validation Commands

```bash
uv run pytest
uv run python -m kg.validation
```

## Evidence To Record

- Changed files.
- Validation command output.
- Example validation findings for the current seed set.
- Confirmation that no external ontology IDs, release IDs, license status, or
  access dates were claimed as verified.
- PRD sections that remain unimplemented.

## Reachability / Demo Proof

At minimum, `uv run python -m kg.validation` should report:

- all required seed files present and parseable;
- graph node/edge schema validation pass;
- ontology lock status remains `todo_unverified`;
- `verified` remains `false`;
- no validation errors for the current seed set.

## Cross-Doc Impact

Do not rewrite the PRD. Update `GOAL.md` only if the current slice changes
again.

## Out Of Scope

- Live ontology downloads.
- Pinning real SNOMED/OPE/COPPER IDs.
- SHACL runtime safety logic.
- Replacing local graph traversal with RDF/OWL runtime behavior.
- New product behavior beyond validation and sidecar scaffolding.

## Stop Conditions

- Validation would require claiming unverified ontology metadata.
- A human explicitly asks to pin real ontology IDs or license status without
  providing verified source data.
- A human explicitly chooses another implementation stack.
