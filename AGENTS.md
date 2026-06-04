# AGENTS.md

## Source of Truth

For FitGraph KG work, follow these files in order:

1. Latest direct user instruction.
2. `docs/kg-module-prd.md`.
3. `GOAL.md`.
4. The active brief named in `GOAL.md`.
5. `executor-reviewer-pair-programming.md`.
6. `docs/autonomous-workflow/`.
7. Existing repo conventions and tests.

## Workflow Rules

- Keep implementation slices small and reviewable.
- Preserve deterministic graph behavior over LLM-driven eligibility.
- Do not use vector search for safety enforcement.
- Do not claim ontology IDs, SNOMED codes, or license status are pinned unless
  `graph/ontology-lock.json` contains the verified value.
- Every autonomous executor turn must leave a session log under
  `docs/session-logs/`.
- Every reviewer turn must leave a decision under `docs/reviewer-messages/`.
- Use exact git add paths for scoped commits.

