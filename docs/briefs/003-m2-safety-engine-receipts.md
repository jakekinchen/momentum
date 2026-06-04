# Slice Brief 003 - M2 Safety Engine And Decision Receipts

**Date:** 2026-06-04

## Objective

Implement the smallest deterministic safety-engine slice that evaluates a tiny
exercise candidate set, collects all applicable hard/soft reasons, chooses a
primary severity by the PRD lattice, and emits decision receipts with graph
paths.

## Product / Project Value

This slice should prove that FitGraph safety is graph-driven rather than
LLM-improvised. It turns M1's typed resolver constraints into auditable keep/drop
receipts for a few local exercises, while preserving the rule that member safety
and equipment constraints are hard blocks.

## Acceptance Criteria

- Add a tiny candidate exercise seed set with enough local graph facts to test:
  - a knee-stressing loaded squat or similar exercise;
  - a deadlift-family variation;
  - an equipment-blocked barbell exercise;
  - a safe lower-impact alternative candidate.
- Add local `Exercise -REQUIRES-> Equipment`, `Exercise -STRESSES-> BodyRegion`,
  and `Exercise -VARIANT_OF-> ExerciseFamily` edges as needed.
- Add a minimal safety rule seed for active knee restriction behavior without
  claiming external ontology IDs.
- `kg.safety` evaluates candidates deterministically from local graph facts and
  typed constraints.
- The evaluator collects all applicable reasons, not only the first reason.
- The evaluator chooses `primary_severity` using the PRD lattice:
  `MEDICAL_HARD_BLOCK > EQUIPMENT_HARD_BLOCK > PROMPT_EXCLUSION >
  MEMBER_STRONG_DISLIKE > SOFT_PENALTY > BOOST`.
- Decision receipts include:
  - `decision`
  - `primary_severity`
  - `reason_codes`
  - `primary_reason_code`
  - `graph_paths`
  - `constraint_fingerprint`
  - `graph_version`
  - `ruleset_version`
  - `ontology_lock_version`
- Tests prove:
  - missing or disallowed equipment creates an `EQUIPMENT_HARD_BLOCK`;
  - `exclude deadlifts` blocks a deadlift-family variation through local
    `VARIANT_OF` closure;
  - active knee restriction blocks a candidate through local `STRESSES` /
    `PART_OF` paths;
  - a safe candidate can be selected;
  - a candidate with multiple reasons records secondary reasons and chooses the
    highest-priority primary severity.
- The executor session log records exactly what was implemented and what remains
  PRD-pending.

## Expected Files

- `kg/safety.py`
- `kg/graph_store.py`
- `kg/provenance.py`
- `graph/exercise_kg.seed.json`
- `graph/safety_rules.seed.json`
- `graph/provenance_schema.json` only if receipt schema wording must be tightened
- `tests/test_safety.py`
- `docs/session-logs/003-executor-m2-safety-engine-receipts.md`

## Test Plan

- Prefer `uv run pytest`.
- Run `uv run python -m kg.validation` after seed changes.
- Include focused tests for severity ordering and all-reason collection.

## Validation Commands

```bash
uv run pytest
uv run python -m kg.validation
```

## Evidence To Record

- Changed files.
- Validation command output.
- Candidate examples and emitted decision receipts.
- Graph paths proving each hard block.
- Confirmation that no vector retrieval or LLM output decides eligibility.
- PRD sections that remain unimplemented.

## Reachability / Demo Proof

At minimum, tests should prove a deterministic call such as
`evaluate_candidates(...)` returns:

- filtered receipt for a barbell exercise when barbell is unavailable;
- filtered receipt for a deadlift variation when `exclude deadlifts` is active;
- filtered receipt for a loaded knee-stressing exercise under an active knee
  restriction;
- selected receipt for a safe candidate from the tiny seed set.

## Cross-Doc Impact

Do not rewrite the PRD. Update `GOAL.md` only if the current slice changes
again.

## Out Of Scope

- Full workout generation.
- Alternative scoring.
- Coach Copilot retrieval.
- Full Jordan member graph ingestion.
- Fuzzy or embedding resolver expansion.
- Live ontology downloads, external account setup, or pinned SNOMED/OPE/COPPER
  IDs.

## Stop Conditions

- The current graph shape cannot express required safety paths for a concrete
  reason.
- Decision receipts would require unverifiable ontology claims.
- A human explicitly chooses another implementation stack.
