# Reviewer Message 005 - M4 Member Context And Copilot Fact Cards

Date: 2026-06-04
Role: Reviewer / Planner
Reviewed commit: `b5c7792 feat: add m4 member fact cards`
Active brief reviewed: `docs/briefs/005-m4-member-context-fact-cards.md`

## Decision

CONTINUE

## Findings

No blocking findings.

## Evidence Reviewed

- `git status --short --branch` reported a clean `main` worktree before this
  reviewer update.
- Latest executor log:
  `docs/session-logs/005-executor-m4-member-context-fact-cards.md`.
- `graph/member_kg.seed.json` contains the required tiny Jordan member context:
  `Member`, `Goal`, `EquipmentAvailability`, `InjuryEpisode`, two
  `AdherenceObservation` records, and `SourceSpan`.
- `kg.member_retrieval` exposes deterministic direct graph query functions for
  available equipment, active injuries, goals, and adherence trend.
- Missing member data returns an explicit no-supporting-fact card.
- Tests prove fact-card output and missing-data behavior.

## Validation Replayed

```bash
uv run pytest
```

Result:

```text
collected 28 items
tests/test_alternatives.py .....
tests/test_graph_store.py ...
tests/test_imports.py .
tests/test_member_retrieval.py .....
tests/test_resolver.py .....
tests/test_safety.py .......
tests/test_validation.py ..
28 passed in 0.05s
```

```bash
uv run python -m kg.validation
```

Result excerpt:

```json
{
  "graph_version": "fitgraph-kg-m4-member-v0",
  "ruleset_version": "ruleset-m2-safety-v0",
  "ontology_lock_version": "ontology-lock-m0-unverified",
  "ontology_status": "todo_unverified",
  "node_count": 28,
  "edge_count": 31,
  "validation_status": "pass",
  "verified": false
}
```

## Acceptance Criteria Check

- Tiny member context seed with required node types: satisfied.
- Local member-context edges for direct graph queries: satisfied.
- Direct query functions for equipment, injuries, goals, and adherence trend:
  satisfied.
- Each query returns deterministic `FactCard` values with claim, confidence,
  source nodes, and query: satisfied.
- Missing data does not invent a claim: satisfied.
- Tests cover graph-backed equipment, injury, goals, adherence trend, and
  missing data: satisfied.
- Executor session log records implemented scope and PRD-pending work:
  satisfied.

## Reviewer Notes

M4 is appropriately scoped. It proves direct graph-backed fact cards before LLM
prose without claiming vector retrieval, hybrid retrieval, full member history,
workout generation, or verified ontology metadata.

The next executor should move to M5 with ontology sidecar and validation
hardening. Preserve the current truth that ontology IDs and license metadata are
unverified unless `graph/ontology-lock.json` pins verified values.

## Next Brief

`docs/briefs/006-m5-ontology-sidecar-validation.md`
