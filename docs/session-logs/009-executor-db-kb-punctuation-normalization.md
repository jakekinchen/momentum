# Executor Session Log 009 - DB/KB Punctuation Normalization

## Slice

Active brief: `docs/briefs/008-only-db-kb-equipment-resolution.md`

Reviewer nudge corrected:
`docs/reviewer-messages/008-review-only-db-kb-equipment-resolution.md`
identified that `resolve_text("Only DB and KB.")` returned an
`UnresolvedConcept` because terminal punctuation stayed attached to `kb`.

Smallest useful slice completed: deterministic resolver normalization now
strips harmless boundary punctuation before local graph alias matching, and a
focused regression test proves the exact PRD API prompt fragment
`Only DB and KB.` resolves to hard typed DB/KB equipment constraints.

## Files Changed

- `kg/resolver.py`
- `tests/test_resolver.py`
- `docs/session-logs/009-executor-db-kb-punctuation-normalization.md`

## Implementation Evidence

- Added boundary-punctuation stripping to the existing `_normalize` function.
- Preserved deterministic local graph label and alias matching.
- Preserved the original `source_text` value on returned constraints.
- Added `test_resolves_prd_db_kb_subset_with_terminal_punctuation`.
- Did not change graph seed data, safety logic, alternatives logic, ontology
  metadata, or workflow control files.

## Pre-Fix Reproduction

Direct command before the edit showed:

```text
resolve_text("only dumbbells and kettlebell") -> Equipment:dumbbell, Equipment:kettlebell
resolve_text("only db and kb") -> Equipment:dumbbell, Equipment:kettlebell
resolve_text("Only DB and KB.") -> UnresolvedConcept value="only db and kb."
```

## Validation

- `bash scripts/agent_thread_status.sh`
  - Passed.
  - Stop sentinel absent.
  - Active brief: `docs/briefs/008-only-db-kb-equipment-resolution.md`.
  - Status summary: `agent thread status clean`.
- `UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run pytest tests/test_resolver.py`
  - Passed: `8 passed in 0.02s`.
- `bash scripts/validate_resume_brief.sh docs/briefs/008-only-db-kb-equipment-resolution.md`
  - Passed.
  - Summary: `resume brief validation clean`.
- `UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run pytest tests/test_resolver.py tests/test_safety.py tests/test_alternatives.py`
  - Passed: `22 passed in 0.02s`.
- `UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run pytest`
  - Passed: `85 passed in 11.22s`.
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
    `docs/session-logs/009-executor-db-kb-punctuation-normalization.md`.
- `node scripts/audit_codex_pair_state.mjs`
  - Passed after this log was written.
  - Stop sentinel absent.
  - Current slice: `docs/briefs/008-only-db-kb-equipment-resolution.md`.
  - Latest executor log:
    `docs/session-logs/009-executor-db-kb-punctuation-normalization.md`.
  - Flag: loop process reported `pid: 36295 (not running)`.
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

constraints = resolve_text("Only DB and KB.")
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
    "receipt_summary": [
        {
            "exercise_id": receipt.exercise_id,
            "decision": receipt.decision,
            "primary_severity": receipt.primary_severity,
            "primary_reason_code": receipt.primary_reason_code,
            "graph_paths": receipt.graph_paths,
        }
        for receipt in receipts
    ],
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
resolved_constraints=[
  Equipment:dumbbell hard=True source_text="Only DB and KB." safety_behavior=allowed_equipment_only,
  Equipment:kettlebell hard=True source_text="Only DB and KB." safety_behavior=allowed_equipment_only
]

available_equipment=[
  "Equipment:dumbbell",
  "Equipment:kettlebell"
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

Workout-candidate result under the same exact PRD prompt fragment:

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

## Product Guardrails

- Deterministic graph behavior preserved.
- `MAPS_TO` remains ontology audit metadata only.
- No vector search was introduced for safety enforcement.
- No LLM path was introduced for eligibility or safety.
- No ontology IDs, SNOMED codes, release IDs, access dates, or license status
  were claimed as verified.
- `graph/ontology-lock.json` remains explicitly unverified.

## Reviewer Flags

- This is a tactical correction to the existing DB/KB slice, not a new product
  expansion.
- The exact PRD API prompt fragment `Only DB and KB.` now reaches the same
  resolver, safety, and alternatives path as the earlier punctuation-free
  DB/KB phrases.

## Remaining PRD-Pending Work

- Broader Jordan equipment expansion beyond the DB/KB golden case.
- Additional prompt examples such as `bad lower back`.
- Plyometric exercise coverage.
- Richer Coach Copilot sleep, churn, and coach-brief fact-card examples.

## Next Suggested Slice

Reviewer should re-audit the nudge correction. If accepted, the next smallest
useful EOD slice is either a PRD acceptance audit and `STOP` decision if the
current coverage is sufficient, or a new focused brief for one remaining golden
gap such as `bad lower back` resolver and safety coverage.
