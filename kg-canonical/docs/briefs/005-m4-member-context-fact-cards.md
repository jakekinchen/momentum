# Slice Brief 005 - M4 Member Context And Copilot Fact Cards

**Date:** 2026-06-04

## Objective

Implement the smallest member-context graph and Coach Copilot fact-card retrieval
slice using direct deterministic graph queries.

## Product / Project Value

This slice should prove that Coach Copilot answers are grounded in graph-backed
fact cards before any LLM prose. Missing member data should stay explicit
instead of being invented.

## Acceptance Criteria

- Populate `graph/member_kg.seed.json` with a tiny member context for one member,
  including:
  - `Member`
  - `Goal`
  - `EquipmentAvailability`
  - `InjuryEpisode`
  - at least two `AdherenceObservation` records
  - at least one `SourceSpan`
- Add local member-context edges needed for direct graph queries.
- `kg.member_retrieval` exposes deterministic direct graph query functions for:
  - available equipment;
  - active injuries;
  - goals;
  - adherence trend.
- Each query returns `FactCard` values with:
  - `claim`
  - `confidence == "deterministic"`
  - `source_nodes`
  - `query`
- Missing data returns a fact card or explicit result stating the graph has no
  supporting fact. Do not synthesize absent member data.
- Tests prove:
  - available equipment is returned from graph data;
  - active injury fact card is source-backed;
  - goals are returned from graph data;
  - adherence trend compares two graph observations;
  - missing data does not invent a claim.
- The executor session log records exactly what was implemented and what remains
  PRD-pending.

## Expected Files

- `kg/member_retrieval.py`
- `kg/graph_store.py` only if shared graph loading helpers are needed
- `graph/member_kg.seed.json`
- `tests/test_member_retrieval.py`
- `docs/session-logs/005-executor-m4-member-context-fact-cards.md`

## Test Plan

- Prefer `uv run pytest`.
- Run `uv run python -m kg.validation` after seed changes.
- Include tests for direct graph retrieval and missing-data behavior.

## Validation Commands

```bash
uv run pytest
uv run python -m kg.validation
```

## Evidence To Record

- Changed files.
- Validation command output.
- Example fact cards.
- Confirmation that LLM/prose generation is not part of this slice.
- PRD sections that remain unimplemented.

## Reachability / Demo Proof

At minimum, a deterministic call should prove:

- `available_equipment("Member:jordan")` returns graph-backed equipment facts.
- `active_injuries("Member:jordan")` returns the active knee issue.
- `adherence_trend("Member:jordan")` returns a deterministic comparison from
  two observations.
- an unknown member returns an explicit no-supporting-fact result.

## Cross-Doc Impact

Do not rewrite the PRD. Update `GOAL.md` only if the current slice changes
again.

## Out Of Scope

- LLM prose generation.
- Vector retrieval.
- Hybrid retrieval over messages.
- Full Jordan history ingestion.
- Workout generation.
- Live ontology downloads or pinned SNOMED/OPE/COPPER IDs.

## Stop Conditions

- Fact cards would require inventing member data absent from the graph.
- Direct graph query support is blocked by the current seed format for a
  concrete reason.
- A human explicitly chooses another implementation stack.
