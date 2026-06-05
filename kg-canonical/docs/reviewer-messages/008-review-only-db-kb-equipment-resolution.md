# Reviewer Message 008 - Only DB/KB Equipment Resolution

Date: 2026-06-04
Role: Reviewer / Planner
Reviewed commit: `de33ae4 feat: resolve db kb equipment subset`
Active brief reviewed: `docs/briefs/008-only-db-kb-equipment-resolution.md`

## Decision

NUDGE

## Findings

One tactical correction is needed before moving to another slice.

The DB/KB subset behavior works for the active brief's punctuation-free phrase,
but it does not handle the exact PRD API prompt form with terminal punctuation:
`Only DB and KB.` resolves to `UnresolvedConcept`. The PRD API example at
`docs/kg-module-prd.md` uses `Only DB and KB.`, so the current slice should add a
small deterministic normalization/test correction before the reviewer plans new
work.

Evidence anchor:

```text
docs/kg-module-prd.md:541-545
Request prompt: "Build a 50-minute lower-body session. Exclude deadlifts. Only DB and KB."

direct command:
resolve_text("only dumbbells and kettlebell") -> Equipment:dumbbell, Equipment:kettlebell
resolve_text("only db and kb") -> Equipment:dumbbell, Equipment:kettlebell
resolve_text("Only DB and KB.") -> UnresolvedConcept value="only db and kb."
```

## Evidence Reviewed

- `git status --short --branch` reported a clean `main` worktree before this
  reviewer update.
- Latest executor log:
  `docs/session-logs/008-executor-only-db-kb-equipment-resolution.md`.
- Latest commit `de33ae4` changed only the resolver, local seed graph, focused
  tests, and executor session log for the DB/KB slice.
- `kg/resolver.py` now resolves `only ...` equipment subsets through local graph
  aliases and marks them hard with `safety_behavior="allowed_equipment_only"`.
- `graph/exercise_kg.seed.json` adds local `Equipment:dumbbell` aliases and
  `Exercise:dumbbell_floor_press`.
- Tests prove hard equipment filtering and alternatives for
  `only dumbbells and kettlebell`.
- Direct runtime proof confirmed selected DB/KB-compatible exercises are
  `Exercise:dumbbell_floor_press` and `Exercise:kettlebell_deadlift`, while
  `Exercise:barbell_bench_press` and `Exercise:glute_bridge` are filtered with
  `EQUIPMENT_HARD_BLOCK` for missing equipment.

## Validation Replayed

```bash
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run pytest tests/test_resolver.py tests/test_safety.py tests/test_alternatives.py
```

Result:

```text
21 passed in 0.03s
```

```bash
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run pytest
```

Result:

```text
84 passed in 12.36s
```

```bash
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run python -m kg.validation
```

Result excerpt:

```json
{
  "validation_status": "pass",
  "schema_validation_status": "pass",
  "ontology_status": "todo_unverified",
  "verified": false,
  "node_count": 30,
  "edge_count": 34
}
```

```bash
bash scripts/audit_autonomous_workflow.sh
node scripts/audit_codex_pair_state.mjs
```

Result:

```text
workflow audit clean
head: de33ae4 feat: resolve db kb equipment subset
stop sentinel: absent
current slice: docs/briefs/008-only-db-kb-equipment-resolution.md
pair-state loop process: pid 79208 (not running)
```

## Acceptance Criteria Check

- Deterministic graph behavior over LLM-driven eligibility: satisfied for the
  covered punctuation-free DB/KB phrase.
- No vector search was introduced for safety enforcement: satisfied.
- No unverified ontology IDs, SNOMED codes, release IDs, access dates, or
  license status were claimed: satisfied.
- Local runtime aliases for `dumbbell`, `dumbbells`, `db`, `kettlebell`, and
  `kb`: satisfied.
- Hard DB/KB equipment subset filtering through safety receipts: satisfied for
  `only dumbbells and kettlebell`.
- Alternatives use the selected safe pool under the DB/KB subset: satisfied.
- Exact PRD API prompt form `Only DB and KB.`: needs tactical correction.

## Reviewer Notes

Do not broaden this into a new product slice yet. Keep the correction small:
make resolver normalization accept the exact PRD API punctuation around DB/KB
equipment subset prompts, add a focused test for `Only DB and KB.`, rerun the
focused and full validation set, and update the executor log.

No next brief was written because the decision is `NUDGE`; `GOAL.md` should
remain pointed at `docs/briefs/008-only-db-kb-equipment-resolution.md` until this
slice is corrected or explicitly redirected.
