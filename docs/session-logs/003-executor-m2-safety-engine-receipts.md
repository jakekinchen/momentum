# Executor Session Log 003 - M2 Safety Engine And Decision Receipts

Date: 2026-06-04
Recorded at: 2026-06-04T17:39:24Z
Role: Executor
Active brief: `docs/briefs/003-m2-safety-engine-receipts.md`

## Slice Implemented

Implemented the smallest deterministic M2 safety-engine slice:

- Expanded `graph/exercise_kg.seed.json` with a tiny exercise candidate set:
  - `Exercise:goblet_squat`
  - `Exercise:kettlebell_deadlift`
  - `Exercise:barbell_bench_press`
  - `Exercise:glute_bridge`
- Added local `REQUIRES`, `STRESSES`, and `VARIANT_OF` edges.
- Added `SafetyRule:avoid_loaded_knee_flexion` in
  `graph/safety_rules.seed.json`.
- Added typed graph helpers for node lookup by type and `PART_OF` path proofs.
- Implemented `kg.safety.evaluate_candidates(...)`.
- Added deterministic receipt fingerprints through `kg.provenance`.
- Added tests for equipment blocks, deadlift-family prompt exclusion, active
  knee restriction, safe selection, all-reason collection, severity ordering,
  and no-LLM/no-vector policy.

This slice does not implement workout generation, alternative scoring, Coach
Copilot retrieval, fuzzy resolver expansion, embedding fallback, full Jordan
member graph ingestion, or verified ontology IDs.

## Files Changed

- `graph/exercise_kg.seed.json`
- `graph/safety_rules.seed.json`
- `kg/graph_store.py`
- `kg/provenance.py`
- `kg/safety.py`
- `kg/validation.py`
- `tests/test_safety.py`
- `tests/test_validation.py`
- `docs/session-logs/003-executor-m2-safety-engine-receipts.md`

## Validation

### `uv run pytest`

```text
collected 18 items

tests/test_graph_store.py ...
tests/test_imports.py .
tests/test_resolver.py .....
tests/test_safety.py .......
tests/test_validation.py ..

18 passed in 0.05s
```

### `uv run python -m kg.validation`

```json
{
  "graph_version": "fitgraph-kg-m2-safety-v0",
  "ruleset_version": "ruleset-m2-safety-v0",
  "ontology_lock_version": "ontology-lock-m0-unverified",
  "ontology_status": "todo_unverified",
  "required_seed_count": 6,
  "present_seed_count": 6,
  "parseable_seed_count": 6,
  "node_count": 14,
  "edge_count": 12,
  "validation_errors": [],
  "validation_status": "pass",
  "verified": false
}
```

## Receipt Evidence

`Exercise:barbell_bench_press` with no barbell available:

```text
decision=filtered
primary_severity=EQUIPMENT_HARD_BLOCK
reason_codes=("MISSING_EQUIPMENT:barbell",)
graph_paths=("Exercise:barbell_bench_press -REQUIRES-> Equipment:barbell",)
```

`Exercise:kettlebell_deadlift` with `exclude deadlifts`:

```text
decision=filtered
primary_severity=PROMPT_EXCLUSION
reason_codes=("PROMPT_EXCLUDED_FAMILY:deadlift_family",)
graph_paths=("Exercise:kettlebell_deadlift -VARIANT_OF-> ExerciseFamily:deadlift_family",)
```

`Exercise:goblet_squat` with active knee restriction:

```text
decision=filtered
primary_severity=MEDICAL_HARD_BLOCK
reason_codes=("ACTIVE_KNEE_RESTRICTION",)
graph_paths=(
  "Exercise:goblet_squat -STRESSES-> BodyRegion:left_knee",
  "BodyRegion:left_knee -PART_OF-> BodyRegion:knee",
  "SafetyRule:avoid_loaded_knee_flexion -USES_CONCEPT-> BodyRegion:knee"
)
```

`Exercise:glute_bridge` with active knee restriction:

```text
decision=selected
primary_severity=BOOST
reason_codes=("PASSED_SAFETY",)
graph_paths=()
```

`Exercise:goblet_squat` with active knee restriction and missing kettlebell:

```text
decision=filtered
primary_severity=MEDICAL_HARD_BLOCK
reason_codes=("ACTIVE_KNEE_RESTRICTION", "MISSING_EQUIPMENT:kettlebell")
primary_reason_code=ACTIVE_KNEE_RESTRICTION
```

## Determinism And Safety Policy

- Eligibility is decided by local graph edges and typed constraints.
- `SafetyRule:avoid_loaded_knee_flexion` uses local `BodyRegion:knee`.
- `graph/safety_rules.seed.json` explicitly records:
  - `deterministic_graph_traversal_decides_safety: true`
  - `llm_decides_safety: false`
  - `vector_search_for_safety_enforcement: false`
- `graph/ontology-lock.json` remains unverified. No OPE, COPPER, or SNOMED CT
  IDs, release IDs, access dates, or license statuses were pinned.

## PRD-Pending Work

- Alternative selection from the already-safe pool.
- Full workout candidate API.
- Richer movement patterns, target muscles, and exercise metadata.
- Member preferences, dislikes, adherence/churn context, and soft penalties.
- Full Jordan member graph ingestion.
- Coach Copilot graph-backed fact cards.
- Fuzzy resolver expansion and embedding fallback for non-safety lookup only.
- Verified ontology lockfile metadata.

## Next Suggested Slice

Move to M3 only after reviewer approval if the reviewer considers M2 complete.
The next useful implementation slice is alternatives/workout candidate API:
derive alternatives from already-safe receipts and prove filtered exercises never
source alternatives from unsafe candidates.
