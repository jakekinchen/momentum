# Reviewer Message 004 - M3 Alternatives And Workout Candidate API

Date: 2026-06-04
Role: Reviewer / Planner
Reviewed commit: `6e2c922 feat: add m3 alternatives api`
Active brief reviewed: `docs/briefs/004-m3-alternatives-workout-candidates.md`

## Decision

CONTINUE

## Findings

No blocking findings.

## Evidence Reviewed

- `git status --short --branch` reported a clean `main` worktree before this
  reviewer update.
- Latest executor log:
  `docs/session-logs/004-executor-m3-alternatives-workout-candidates.md`.
- `graph/exercise_kg.seed.json` contains local `TARGETS` and `HAS_PATTERN`
  edges plus tiny `MuscleGroup` and `MovementPattern` nodes.
- `kg.alternatives.select_alternatives(...)` builds the safe pool only from
  receipts whose `decision == "selected"`.
- `kg.alternatives.build_workout_candidates(...)` returns selected receipts,
  filtered receipts, and alternative records from one safety result set.
- Tests prove the filtered candidates never appear as alternatives and
  `Exercise:glute_bridge` is the selected alternative for the tiny unsafe set.

## Validation Replayed

```bash
uv run pytest
```

Result:

```text
collected 23 items
tests/test_alternatives.py .....
tests/test_graph_store.py ...
tests/test_imports.py .
tests/test_resolver.py .....
tests/test_safety.py .......
tests/test_validation.py ..
23 passed in 0.05s
```

```bash
uv run python -m kg.validation
```

Result excerpt:

```json
{
  "graph_version": "fitgraph-kg-m3-alternatives-v0",
  "ruleset_version": "ruleset-m2-safety-v0",
  "ontology_lock_version": "ontology-lock-m0-unverified",
  "ontology_status": "todo_unverified",
  "node_count": 21,
  "edge_count": 23,
  "validation_status": "pass",
  "verified": false
}
```

## Acceptance Criteria Check

- Tiny local `TARGETS` and `HAS_PATTERN` graph facts: satisfied.
- Alternatives selected only from `decision == "selected"` receipts: satisfied.
- PRD-shaped scoring components for target overlap, movement pattern,
  equipment, and priority tier: satisfied.
- Deterministic alternative records include filtered ID, alternative ID,
  derived-from, score components, score, and graph paths: satisfied.
- Minimal workout-candidate function returns selected receipts, filtered
  receipts, and alternatives: satisfied.
- Tests cover selected-only alternatives, filtered exercise exclusion, safe
  lower-impact alternative, empty safe pool, and deterministic ordering:
  satisfied.
- Executor session log records implemented scope and PRD-pending work:
  satisfied.

## Reviewer Notes

M3 is appropriately scoped. It proves alternatives are derived from the already
safe pool without claiming full workout plan generation, member context, Coach
Copilot retrieval, fuzzy matching, embedding fallback, or verified ontology
metadata.

The next executor should move to M4 with a tiny member-context graph and direct
fact-card retrieval. Keep LLM behavior downstream of fact cards: the graph
retrieves facts, and prose may summarize only those facts.

## Next Brief

`docs/briefs/005-m4-member-context-fact-cards.md`
