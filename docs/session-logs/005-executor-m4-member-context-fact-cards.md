# Executor Session Log 005 - M4 Member Context And Copilot Fact Cards

Date: 2026-06-04
Recorded at: 2026-06-04T17:48:25Z
Role: Executor
Active brief: `docs/briefs/005-m4-member-context-fact-cards.md`

## Slice Implemented

Implemented the smallest deterministic M4 member-context and fact-card slice:

- Populated `graph/member_kg.seed.json` with tiny Jordan member context:
  - `Member`
  - `Goal`
  - `EquipmentAvailability`
  - `InjuryEpisode`
  - two `AdherenceObservation` records
  - one `SourceSpan`
- Added local member-context edges for direct graph queries.
- Added `load_member_graph(...)` and `load_member_context_graph(...)`.
- Implemented deterministic direct query functions in `kg.member_retrieval`:
  - `available_equipment(...)`
  - `active_injuries(...)`
  - `goals(...)`
  - `adherence_trend(...)`
- Added explicit missing-data fact cards that say the graph has no supporting
  fact.
- Added tests for graph-backed equipment, injury, goals, adherence trend, and
  missing-member behavior.

No LLM prose generation, vector retrieval, hybrid retrieval over messages, full
Jordan history ingestion, workout generation, or verified ontology IDs were
implemented.

## Files Changed

- `graph/member_kg.seed.json`
- `kg/graph_store.py`
- `kg/ingest.py`
- `kg/member_retrieval.py`
- `kg/validation.py`
- `tests/test_member_retrieval.py`
- `tests/test_safety.py`
- `tests/test_validation.py`
- `docs/session-logs/005-executor-m4-member-context-fact-cards.md`

## Validation

### `uv run pytest`

```text
collected 28 items

tests/test_alternatives.py .....
tests/test_graph_store.py ...
tests/test_imports.py .
tests/test_member_retrieval.py .....
tests/test_resolver.py .....
tests/test_safety.py .......
tests/test_validation.py ..

28 passed in 0.06s
```

### `uv run python -m kg.validation`

```json
{
  "graph_version": "fitgraph-kg-m4-member-v0",
  "ruleset_version": "ruleset-m2-safety-v0",
  "ontology_lock_version": "ontology-lock-m0-unverified",
  "ontology_status": "todo_unverified",
  "required_seed_count": 6,
  "present_seed_count": 6,
  "parseable_seed_count": 6,
  "node_count": 28,
  "edge_count": 31,
  "validation_errors": [],
  "validation_status": "pass",
  "verified": false
}
```

## Fact-Card Evidence

`available_equipment("Member:jordan")`:

```text
claim="Jordan has available equipment: kettlebell, yoga mat."
confidence="deterministic"
source_nodes=("EquipmentAvailability:jordan_home_equipment", "SourceSpan:jordan_intake_2026_06_04")
query="member_retrieval.available_equipment"
```

`active_injuries("Member:jordan")`:

```text
claim="Jordan has an active left knee injury episode since 2026-05-10."
confidence="deterministic"
source_nodes=("InjuryEpisode:left_knee_issue_since_2026_05_10", "SourceSpan:jordan_intake_2026_06_04")
query="member_retrieval.active_injuries"
```

`goals("Member:jordan")`:

```text
claim="Jordan's active goal is: Build lower-body strength without aggravating left knee."
confidence="deterministic"
source_nodes=("Goal:jordan_lower_body_strength", "SourceSpan:jordan_intake_2026_06_04")
query="member_retrieval.goals"
```

`adherence_trend("Member:jordan")`:

```text
claim="Adherence declined from 100% (4/4) on 2026-05-19 to 50% (2/4) on 2026-06-02."
confidence="deterministic"
source_nodes=("AdherenceObservation:jordan_week_2026_05_19", "AdherenceObservation:jordan_week_2026_06_02")
query="member_retrieval.adherence_trend"
```

`available_equipment("Member:unknown")`:

```text
claim="The graph has no supporting fact for Member:unknown."
confidence="deterministic"
source_nodes=()
query="member_retrieval.available_equipment"
```

## Determinism And Retrieval Policy

- Fact cards are retrieved from local member graph nodes and edges.
- Missing member data returns an explicit no-supporting-fact card.
- LLM/prose generation is not part of this slice.
- Vector retrieval is not used.
- `graph/ontology-lock.json` remains unverified. No OPE, COPPER, or SNOMED CT
  IDs, release IDs, access dates, or license statuses were pinned.

## PRD-Pending Work

- Hybrid retrieval over messages and coach notes.
- Sleep, workout completion, churn risk, coach brief, and chart-data queries.
- Richer member history ingestion.
- LLM summarization constrained to fact cards.
- Verified ontology lockfile metadata.
- Production RDF/SKOS/PROV/SHACL sidecar hardening.

## Next Suggested Slice

Move to M5 only after reviewer approval if the reviewer considers M4 complete.
The next useful implementation slice is ontology sidecar and validation:
tighten mapping/receipt schema validation, preserve the unverified lockfile
truth, and add optional export/validation scaffolding without claiming external
ontology IDs.
