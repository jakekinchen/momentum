# Executor Session Log 008 - Only DB/KB Equipment Resolution

## Slice

Active brief: `docs/briefs/008-only-db-kb-equipment-resolution.md`

Smallest useful slice completed: resolved `only dumbbells and kettlebell` into
hard typed allowed-equipment constraints, then proved those constraints can
drive the existing hard equipment subset filter and workout-candidate
alternative path.

## Files Changed

- `kg/resolver.py`
- `graph/exercise_kg.seed.json`
- `tests/test_resolver.py`
- `tests/test_safety.py`
- `tests/test_alternatives.py`
- `docs/session-logs/008-executor-only-db-kb-equipment-resolution.md`

## Implementation Evidence

- Added deterministic local parsing for `only ...` equipment subset phrases.
- `resolve_text("only dumbbells and kettlebell")` now returns two hard
  positive `Equipment` constraints:
  - `Equipment:dumbbell`
  - `Equipment:kettlebell`
- Each resolved subset constraint has
  `safety_behavior="allowed_equipment_only"`, `verified=False`, and
  `negated=False`.
- Added local runtime graph node `Equipment:dumbbell` with aliases
  `dumbbell`, `dumbbells`, and `db`.
- Reused existing `Equipment:kettlebell` aliases `kettlebell` and `kb`.
- Added one narrow compatible exercise, `Exercise:dumbbell_floor_press`, with
  local `REQUIRES`, `TARGETS`, and `HAS_PATTERN` edges.
- Kept safety decisions in the existing deterministic graph path:
  `evaluate_candidates(..., available_equipment={...}, constraints=...)`.
- Did not add vector search, LLM eligibility, live ontology downloads, or
  verified ontology claims.

## Validation

- `bash scripts/agent_thread_status.sh`
  - Passed.
  - Stop sentinel absent.
  - Active brief: `docs/briefs/008-only-db-kb-equipment-resolution.md`.
  - Status summary: `agent thread status clean`.
- `bash scripts/validate_resume_brief.sh docs/briefs/008-only-db-kb-equipment-resolution.md`
  - Passed.
  - Summary: `resume brief validation clean`.
- `UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run pytest tests/test_resolver.py tests/test_safety.py tests/test_alternatives.py`
  - Passed: `21 passed in 0.03s`.
- `UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run pytest`
  - Passed: `84 passed in 11.95s`.
- `UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run python -m kg.validation`
  - Passed.
  - `validation_status`: `pass`.
  - `schema_validation_status`: `pass`.
  - `ontology_status`: `todo_unverified`.
  - `verified`: `false`.
  - `node_count`: `30`.
  - `edge_count`: `34`.
- `bash scripts/audit_autonomous_workflow.sh`
  - Passed after this log was written.
  - Summary: `workflow audit clean`.
  - Latest executor log:
    `docs/session-logs/008-executor-only-db-kb-equipment-resolution.md`.
- `node scripts/audit_codex_pair_state.mjs`
  - Passed after this log was written.
  - Stop sentinel absent.
  - Current slice: `docs/briefs/008-only-db-kb-equipment-resolution.md`.
  - Latest executor log:
    `docs/session-logs/008-executor-only-db-kb-equipment-resolution.md`.
  - Flag: loop process reported `pid: 79208 (not running)`.
- `git diff --check`
  - Passed.

## Reachability Proof

Direct real command:

```bash
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run python - <<'PY'
from dataclasses import asdict
from json import dumps

from kg.alternatives import build_workout_candidates
from kg.resolver import resolve_text
from kg.safety import evaluate_candidates

constraints = resolve_text("only dumbbells and kettlebell")
available = {
    f"Equipment:{constraint.value}"
    for constraint in constraints
    if constraint.constraint_type == "Equipment"
    and constraint.hard
    and constraint.safety_behavior == "allowed_equipment_only"
}
receipts = evaluate_candidates(
    [
        "Exercise:barbell_bench_press",
        "Exercise:dumbbell_floor_press",
        "Exercise:kettlebell_deadlift",
        "Exercise:glute_bridge",
    ],
    available_equipment=available,
    constraints=constraints,
)
result = build_workout_candidates(receipts, available_equipment=available)
print(dumps({
    "resolved_constraints": [asdict(constraint) for constraint in constraints],
    "available_equipment": sorted(available),
    "receipts": [asdict(receipt) for receipt in receipts],
    "workout_candidates": {
        "selected": [receipt.exercise_id for receipt in result.selected_receipts],
        "filtered": [receipt.exercise_id for receipt in result.filtered_receipts],
        "alternatives": [asdict(record) for record in result.alternatives],
    },
}, indent=2, sort_keys=True))
PY
```

Result excerpts:

```text
available_equipment=[
  "Equipment:dumbbell",
  "Equipment:kettlebell"
]

resolved_constraints=[
  Equipment:dumbbell hard=True safety_behavior=allowed_equipment_only verified=False,
  Equipment:kettlebell hard=True safety_behavior=allowed_equipment_only verified=False
]

Exercise:barbell_bench_press -> filtered
primary_severity=EQUIPMENT_HARD_BLOCK
primary_reason_code=MISSING_EQUIPMENT:barbell
graph_paths=("Exercise:barbell_bench_press -REQUIRES-> Equipment:barbell",)

Exercise:dumbbell_floor_press -> selected
primary_reason_code=PASSED_SAFETY

Exercise:kettlebell_deadlift -> selected
primary_reason_code=PASSED_SAFETY

Exercise:glute_bridge -> filtered
primary_severity=EQUIPMENT_HARD_BLOCK
primary_reason_code=MISSING_EQUIPMENT:yoga_mat
graph_paths=("Exercise:glute_bridge -REQUIRES-> Equipment:yoga_mat",)
```

Workout-candidate result under the same DB/KB subset:

```text
selected=[
  "Exercise:dumbbell_floor_press",
  "Exercise:kettlebell_deadlift"
]
filtered=[
  "Exercise:barbell_bench_press",
  "Exercise:glute_bridge"
]
alternatives=[
  Exercise:barbell_bench_press -> Exercise:dumbbell_floor_press,
  Exercise:glute_bridge -> Exercise:kettlebell_deadlift
]
```

The barbell bench alternative includes graph paths:

```text
Exercise:barbell_bench_press -TARGETS-> MuscleGroup:chest
Exercise:dumbbell_floor_press -TARGETS-> MuscleGroup:chest
Exercise:barbell_bench_press -HAS_PATTERN-> MovementPattern:horizontal_press
Exercise:dumbbell_floor_press -HAS_PATTERN-> MovementPattern:horizontal_press
Exercise:dumbbell_floor_press -REQUIRES-> Equipment:dumbbell
```

## Product Guardrails

- Deterministic graph behavior preserved.
- `MAPS_TO` remains ontology audit metadata only.
- No vector search was introduced for safety enforcement.
- No LLM path was introduced for eligibility or safety.
- No ontology IDs, SNOMED codes, release IDs, access dates, or license status
  were claimed as verified.
- `graph/ontology-lock.json` remains explicitly unverified.

## Reviewer Flags

- The DB/KB golden path is now covered from resolver through safety receipts
  and workout-candidate alternatives.
- The bridge from positive allowed-equipment constraints to
  `available_equipment` is currently explicit at the call site, matching the
  existing safety API. Reviewer should decide whether a future slice should
  promote that extraction into a shared helper.
- `node scripts/audit_codex_pair_state.mjs` passed but reported the background
  loop PID was not running. This is a process-runner concern for Reviewer or
  Manager, not a product-code blocker for this executor slice.

## Remaining PRD-Pending Work

- Broader Jordan equipment expansion beyond the DB/KB golden case.
- Additional prompt examples such as `bad lower back`.
- Plyometric exercise coverage.
- Richer Coach Copilot sleep, churn, and coach-brief fact-card examples.

## Next Suggested Slice

If Reviewer chooses `CONTINUE`, run an EOD acceptance audit against the PRD and
either record `STOP` if coverage is now sufficient or write the next smallest
brief for one remaining golden gap, likely `bad lower back` resolver and safety
coverage.
