# Executor Session Log 004 - M3 Alternatives And Workout Candidate API

Date: 2026-06-04
Recorded at: 2026-06-04T17:43:52Z
Role: Executor
Active brief: `docs/briefs/004-m3-alternatives-workout-candidates.md`

## Slice Implemented

Implemented the smallest M3 alternatives/workout-candidate API:

- Expanded `graph/exercise_kg.seed.json` with tiny `MuscleGroup` and
  `MovementPattern` nodes.
- Added local `TARGETS` and `HAS_PATTERN` edges for the existing M2 candidate
  set.
- Replaced the placeholder `kg.alternatives` implementation with:
  - `AlternativeRecord`
  - `WorkoutCandidateResult`
  - `select_alternatives(...)`
  - `build_workout_candidates(...)`
- Scoring uses PRD-shaped components:
  - target muscle overlap
  - movement pattern similarity
  - equipment preference
  - priority tier
- Alternatives are selected only from safety receipts whose
  `decision == "selected"`.
- Added tests proving unsafe or filtered receipts never enter the alternative
  pool.

This slice does not implement full workout plan generation, Coach Copilot
retrieval, member adherence/churn context, fuzzy resolver expansion, embedding
fallback, or verified ontology IDs.

## Files Changed

- `graph/exercise_kg.seed.json`
- `kg/alternatives.py`
- `kg/validation.py`
- `tests/test_alternatives.py`
- `tests/test_safety.py`
- `tests/test_validation.py`
- `docs/session-logs/004-executor-m3-alternatives-workout-candidates.md`

## Validation

### `uv run pytest`

```text
collected 23 items

tests/test_alternatives.py .....
tests/test_graph_store.py ...
tests/test_imports.py .
tests/test_resolver.py .....
tests/test_safety.py .......
tests/test_validation.py ..

23 passed in 0.06s
```

### `uv run python -m kg.validation`

```json
{
  "graph_version": "fitgraph-kg-m3-alternatives-v0",
  "ruleset_version": "ruleset-m2-safety-v0",
  "ontology_lock_version": "ontology-lock-m0-unverified",
  "ontology_status": "todo_unverified",
  "required_seed_count": 6,
  "present_seed_count": 6,
  "parseable_seed_count": 6,
  "node_count": 21,
  "edge_count": 23,
  "validation_errors": [],
  "validation_status": "pass",
  "verified": false
}
```

## Demo Evidence

Safety run with active knee restriction, `exclude deadlifts`, and home
equipment `kettlebell + yoga_mat`:

```text
selected ['Exercise:glute_bridge']
filtered ['Exercise:goblet_squat', 'Exercise:kettlebell_deadlift', 'Exercise:barbell_bench_press']
```

Alternative records:

```text
Exercise:barbell_bench_press => Exercise:glute_bridge
score=0.19
components={'target_overlap': 0.0, 'movement_pattern_similarity': 0.0, 'equipment_preference': 1.0, 'priority_tier': 0.9}

Exercise:goblet_squat => Exercise:glute_bridge
score=0.34
components={'target_overlap': 0.3333333333333333, 'movement_pattern_similarity': 0.0, 'equipment_preference': 1.0, 'priority_tier': 0.9}

Exercise:kettlebell_deadlift => Exercise:glute_bridge
score=0.99
components={'target_overlap': 1.0, 'movement_pattern_similarity': 1.0, 'equipment_preference': 1.0, 'priority_tier': 0.9}
```

The safe pool contains only `Exercise:glute_bridge`, so no filtered exercise can
be returned as an alternative.

## Graph Path Evidence

The `Exercise:goblet_squat` alternative record includes graph paths such as:

```text
Exercise:goblet_squat -TARGETS-> MuscleGroup:glutes
Exercise:glute_bridge -TARGETS-> MuscleGroup:glutes
Exercise:glute_bridge -REQUIRES-> Equipment:yoga_mat
Exercise:glute_bridge -STRESSES-> BodyRegion:hip
```

## Determinism And Safety Policy

- Alternatives are derived from M2 safety receipts, not raw candidate IDs.
- `select_alternatives(...)` builds its safe pool only from receipts with
  `decision == "selected"`.
- Eligibility remains decided by local graph safety evaluation.
- No vector retrieval or LLM output is used for alternatives or safety.
- `graph/ontology-lock.json` remains unverified. No OPE, COPPER, or SNOMED CT
  IDs, release IDs, access dates, or license statuses were pinned.

## PRD-Pending Work

- Full workout plan generation.
- Richer alternative scoring and member preference handling.
- Member adherence/churn context.
- Coach Copilot graph-backed fact cards.
- Fuzzy resolver expansion and embedding fallback for non-safety lookup only.
- Verified ontology lockfile metadata.

## Next Suggested Slice

Move to M4 only after reviewer approval if the reviewer considers M3 complete.
The next useful implementation slice is member-context and Coach Copilot fact
cards: add a tiny member graph, deterministic direct graph queries, and fact
cards that an LLM may summarize without inventing member data.
